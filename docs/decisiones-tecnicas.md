# Decisiones técnicas

Registro de decisiones de arquitectura (ADR). Cada entrada explica el contexto, la decisión, las alternativas descartadas y sus consecuencias.

| # | Decisión |
|---|---|
| [ADR-01](#adr-01--reglas-de-negocio-en-el-motor) | Las reglas de negocio críticas se garantizan en el motor, no en la aplicación |
| [ADR-02](#adr-02--exclusión-gist-en-lugar-de-trigger-para-el-solapamiento) | Exclusión GiST en lugar de un trigger para el solapamiento |
| [ADR-03](#adr-03--rangos-semiabiertos-inicio-fin) | Rangos semiabiertos `[inicio, fin)` |
| [ADR-04](#adr-04--timestamptz-y-zona-horaria-fijada-en-la-base) | `timestamptz` y zona horaria fijada en la base |
| [ADR-05](#adr-05--separar-función-y-proyección) | Separar función y proyección |
| [ADR-06](#adr-06--atributos-derivados-no-editables) | Atributos derivados no editables |
| [ADR-07](#adr-07--when-old-is-distinct-from-new-en-lugar-de-update-of) | `WHEN (OLD IS DISTINCT FROM NEW)` en lugar de `UPDATE OF` |
| [ADR-08](#adr-08--propagación-en-cascada-reutilizando-validaciones) | Propagación en cascada reutilizando validaciones |
| [ADR-09](#adr-09--sqlstate-estándar-en-las-reglas-propias) | SQLSTATE estándar en las reglas propias |
| [ADR-10](#adr-10--pruebas-en-sql-puro-con-concurrencia-real-vía-dblink) | Pruebas en SQL puro con concurrencia real vía `dblink` |
| [ADR-11](#adr-11--tipos-numeric-enum-y-dominios) | Tipos `numeric`, `ENUM` y dominios |

---

## ADR-01 — Reglas de negocio en el motor

**Contexto.** Varias aplicaciones (venta online, taquilla, backoffice de programación) escriben sobre las mismas tablas. Si cada una valida por su cuenta, las reglas se duplican, divergen y, sobre todo, no resisten la concurrencia: dos procesos pueden leer "hay lugar" al mismo tiempo y escribir ambos.

**Decisión.** Las invariantes críticas se expresan como restricciones declarativas cuando es posible (`UNIQUE`, `EXCLUDE`, `CHECK`, FK, dominios) y como triggers PL/pgSQL cuando la regla requiere consultar otras tablas.

**Alternativas descartadas.** Validar solo en la aplicación, o hacerlo con locks explícitos (`SELECT ... FOR UPDATE`) en cada cliente.

**Consecuencias.** Ningún cliente puede saltearse una regla, ni siquiera un `psql` manual. A cambio, la lógica de negocio vive en SQL y hay que probarla en SQL (ADR-10).

## ADR-02 — Exclusión GiST en lugar de trigger para el solapamiento

**Contexto.** R-01 exige que una sala no tenga dos funciones solapadas. La implementación ingenua es un trigger que busca solapamientos con un `SELECT ... WHERE rango && NEW.rango`.

**Decisión.** Restricción de exclusión:
```sql
EXCLUDE USING gist (nro_sala WITH =, rango_ocupacion WITH &&)
```
Para combinar `=` sobre un entero con `&&` sobre un rango en el mismo índice GiST hace falta la extensión `btree_gist`.

**Alternativas descartadas.** Un trigger de validación. Con el aislamiento por defecto (`READ COMMITTED`), el `SELECT` del trigger no ve las filas que otra transacción insertó y todavía no confirmó: dos transacciones concurrentes pueden pasar la validación e insertar funciones solapadas. Evitarlo exigiría `SERIALIZABLE` o un lock explícito sobre la sala.

**Consecuencias.** El motor serializa el conflicto a nivel de índice: la segunda transacción espera a que la primera termine y, si esta confirma, se rechaza con `23P01`. La prueba C-03 lo verifica con dos sesiones reales. El mismo patrón se usa para las vigencias de cartelera (R-12).

## ADR-03 — Rangos semiabiertos `[inicio, fin)`

**Contexto.** Hay que decidir si dos funciones consecutivas, una que termina a las 19:40 y otra que empieza a las 19:40, se solapan.

**Decisión.** Rangos `[inicio, fin)`: el instante final no pertenece al rango.

**Consecuencias.** Las funciones contiguas se aceptan (P-07) y un solapamiento de un minuto se rechaza (N-02). El tiempo de limpieza ya está incluido en `fin` (R-03), así que "contiguas" significa que la sala quedó lista.

## ADR-04 — `timestamptz` y zona horaria fijada en la base

**Contexto.** El modelo original usaba `TIME` para los horarios. Un `TIME` no tiene fecha: no distingue días, no puede representar una función que cruza la medianoche y no admite tipos de rango.

**Decisión.** Instantes en `timestamptz` y rangos en `tstzrange`. `01-schema.sql` fija la zona horaria de la base:
```sql
ALTER DATABASE <base> SET timezone TO 'America/Argentina/Buenos_Aires';
```

**Alternativas descartadas.** `timestamp` sin zona, que es ambiguo si los clientes están en otra zona. Configurar `TZ`/`PGTZ` en el contenedor, que solo afecta a los clientes de ese entorno.

**Consecuencias.** Las funciones de trasnoche se validan como cualquier otra (P-09, N-03). Los literales sin offset se interpretan como hora local y los resultados se muestran con `-03` (P-01), mientras el almacenamiento sigue en UTC.

## ADR-05 — Separar función y proyección

**Contexto.** El modelo original vinculaba la entrada a `(función, asiento)`. Si una función se proyectaba en dos salas, no se podía vender el asiento 1 en ambas, y el trigger de validación de asientos fallaba al obtener más de una sala para la misma función.

**Decisión.** `funcion` es el evento lógico. `proyeccion (nro_sala, id_funcion)` es su ocurrencia en una sala física, y es la dueña del rango de ocupación. `entrada` referencia la proyección con una FK compuesta.

**Consecuencias.** Las funciones multi-sala se modelan con naturalidad (P-05), el asiento se valida contra la capacidad de la sala correcta (R-06) y la unicidad `(nro_sala, id_funcion, nro_asiento)` expresa exactamente la regla de overbooking (R-02).

## ADR-06 — Atributos derivados no editables

**Contexto.** `fecha_hora_fin`, `duracion_total_min` y `rango_ocupacion` se calculan a partir de otros datos. Si el cliente pudiera escribirlos, un rango falso dejaría sin efecto la restricción de exclusión.

**Decisión.** Los triggers `BEFORE` que los calculan se disparan ante **cualquier** `INSERT` o `UPDATE` y sobrescriben el valor enviado.

**Alternativas descartadas.** Columnas `GENERATED ALWAYS AS (...) STORED`: solo pueden usar datos de la misma fila, y la duración depende de `pelicula` y `espacio_publicitario`. Rechazar el UPDATE con un error: también protege, pero obliga a los clientes a conocer qué columnas son derivadas.

**Consecuencias.** El valor persistido siempre es coherente con sus fuentes (P-12). Cada UPDATE sobre `funcion` recalcula el fin, un costo despreciable a este volumen. Ver el Bug 3 en [bugs-encontrados.md](bugs-encontrados.md).

## ADR-07 — `WHEN (OLD IS DISTINCT FROM NEW)` en lugar de `UPDATE OF`

**Contexto.** El trigger que propaga el horario a `proyeccion` se declaraba `AFTER UPDATE OF fecha_hora_inicio, fecha_hora_fin`. `UPDATE OF` solo considera las columnas que figuran en el `SET` de la sentencia, no las que modifica un trigger `BEFORE`. Al cambiar la película, el fin se recalculaba pero no se propagaba, y se aceptaban solapamientos reales (Bug 1).

**Decisión.** Los triggers que reaccionan a valores derivados usan una condición sobre la fila final:
```sql
AFTER UPDATE ON funcion FOR EACH ROW
WHEN (OLD.fecha_hora_inicio IS DISTINCT FROM NEW.fecha_hora_inicio
      OR OLD.fecha_hora_fin IS DISTINCT FROM NEW.fecha_hora_fin)
```

**Consecuencias.** La propagación ocurre sin importar qué columna originó el cambio (P-11, N-05), y la condición evita ejecutar el trigger cuando el horario no cambió. `IS DISTINCT FROM` también trata bien los `NULL`.

## ADR-08 — Propagación en cascada reutilizando validaciones

**Contexto.** Al agregar una pieza a un espacio publicitario en uso cambian su duración y su clasificación. Eso afecta el fin de las funciones (R-03), la compatibilidad etaria (R-05) y la ocupación de las salas (R-01). Las validaciones existían, pero solo se ejecutaban al modificar `funcion` (Bug 2).

**Decisión.** Un trigger sobre `espacio_publicitario` reasigna el mismo espacio a sus funciones:
```sql
UPDATE funcion SET cod_espacio_publicitario = NEW.cod_espacio_publicitario
WHERE cod_espacio_publicitario = NEW.cod_espacio_publicitario;
```
Ese UPDATE, que no cambia ningún valor, dispara la cadena completa de triggers de `funcion` y `proyeccion` (ver `diagramas/flujo-reglas.png`).

**Alternativas descartadas.** Duplicar en el trigger del espacio la validación etaria y el recálculo de horarios: dos implementaciones de la misma regla que pueden divergir.

**Consecuencias.** Cada regla se implementa una sola vez. Si algún eslabón falla, se revierte la sentencia original sobre `compone` (N-06, N-17). La cadena es más difícil de seguir leyendo el código, por eso está documentada en el diagrama de flujo.

## ADR-09 — SQLSTATE estándar en las reglas propias

**Contexto.** Las reglas en PL/pgSQL pueden lanzar errores con cualquier código. El valor por defecto de `RAISE EXCEPTION` es `P0001` (raise_exception), que no distingue un error de negocio de un error de programación.

**Decisión.** Las reglas usan los códigos estándar de violación de integridad: `23514` (check_violation) para condiciones sobre valores y `23503` (foreign_key_violation) para la correspondencia de sucursal. Cada una incluye `MESSAGE` descriptivo y `HINT`.

**Consecuencias.** Un cliente maneja igual una violación de trigger que una de `CHECK`. Como varias reglas comparten `23514`, las pruebas verifican también un fragmento del mensaje para identificar la regla violada.

## ADR-10 — Pruebas en SQL puro con concurrencia real vía `dblink`

**Contexto.** La tesis del proyecto es que el motor protege las reglas incluso bajo concurrencia. Eso hay que demostrarlo con dos transacciones simultáneas reales, no con inserciones secuenciales.

**Decisión.**
- Micro-framework de aserciones en `pg_temp` (`tests/00-helpers.sql`), sin dependencias externas como pgTAP.
- `assert_rechaza` verifica el SQLSTATE exacto y **siempre** revierte la sentencia, incluso si fue aceptada por error, para que un fallo no contamine las pruebas siguientes.
- Los casos positivos y negativos corren dentro de una transacción que se revierte al final.
- Para la concurrencia, `dblink` abre dos sesiones sobre la misma base. La prueba verifica en `pg_stat_activity` que la segunda sesión queda **bloqueada** (`wait_event_type = 'Lock'`) antes de que la primera confirme.

**Alternativas descartadas.** pgTAP, que agrega una extensión a instalar. Un script de shell con dos `psql` en paralelo y `sleep`, que depende de los tiempos y no verifica el bloqueo.

**Consecuencias.** `make test` no necesita nada fuera de la imagen oficial de PostgreSQL. Las pruebas se validaron con una prueba de mutación: con los triggers originales fallan exactamente las pruebas de regresión esperadas.

## ADR-11 — Tipos `numeric`, `ENUM` y dominios

**Decisión.**
- Importes en `numeric(10,2)` en lugar de `float`, que introduce errores de redondeo binario.
- Duraciones en minutos (`smallint`/`integer`) y en segundos para las piezas publicitarias, en lugar de `TIME`.
- Conjuntos cerrados de valores como `ENUM` (`tipo_sala`, `clasificacion_pelicula`, …). La comparación de clasificaciones usa `fn_peso_clasificacion()` y no el orden del `ENUM`.
- Formatos reutilizables como dominios (`email`, `ean13`), para validarlos igual en todas las tablas que los usan.

**Consecuencias.** Agregar un valor a un `ENUM` requiere `ALTER TYPE ... ADD VALUE`, aceptable para catálogos estables como estos. Si se agrega una clasificación nueva, también hay que actualizar `fn_peso_clasificacion()`.
