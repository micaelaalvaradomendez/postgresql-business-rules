# Plan Maestro de Ejecución por Fases — PostgreSQL Business Rules

> **Proyecto de Portafolio:** Caso 2 — Automatización e Integridad Transaccional en PostgreSQL  
> **Subtítulo:** *Normalización 3FN, Restricciones de Exclusión GiST y Lógica de Negocio en Motor con PL/pgSQL.*  
> **Dominio:** Cadena de Cines Sunstar  
> **Ubicación local:** `/home/micaela/postgresql-business-rules/`  
> **Repositorio remoto:** `https://github.com/micaelaalvaradomendez/postgresql-business-rules`  
> **Documento de referencia en portafolio:** `/home/micaela/cuaderno/emprendimiento/portafolio/caso-03-modelo-logica-bd-postgresql.md`

---

## 1. Misión y Alcance del Laboratorio

El objetivo de este proyecto es transformar una base de datos relacional académica en un **laboratorio de referencia profesional, reproducible y dockerizado**, que demuestre que:

> *"Las restricciones declarativas, extensiones especializadas (`btree_gist`) y funciones/triggers en PL/pgSQL pueden y deben garantizar las invariantes de negocio críticas a nivel motor, blindando la integridad de datos frente a condiciones de carrera (race conditions) y accesos concurrentes de múltiples microservicios."*

### Diagnóstico de Fallas del Esquema Base a Subsanar:
1. **Falla de integridad y overbooking en entradas:** La tabla `entrada` asociaba únicamente `(nro_asiento, id_funcion)`. Al permitir que una función se exhiba en varias salas simultáneamente (`proyecta`), impedía vender el mismo número de asiento en salas distintas y provocaba errores en tiempo de ejecución al validar asientos.
2. **Solapamiento temporal en salas físicas:** La entidad `horario` utilizaba el tipo `TIME` sin fecha ni zona horaria, imposibilitando garantizar que una sala no tenga funciones superpuestas entre días o en cruces de medianoche mediante exclusión GiST.
3. **Bloqueo circular (huevo y gallina) en Cartelera/Horario:** El trigger original exigía una función para insertar un horario, pero la función requería obligatoriamente un horario, forzando actualizaciones manuales posteriores con datos inconsistentes.
4. **Desincronización en eliminación de publicidad (`compone`):** Los triggers de duración y clasificación no contemplaban el evento `DELETE`, dejando métricas desactualizadas ante bajas de trailers o anuncios.
5. **Anti-patrones de diseño:** Tipos `float` para importes monetarios, atributos redundantes `id_empleado1` e `id_empleado2` en `trabaja_en`, y falta de vinculación entre `cartelera` y `sucursal`.
6. **Marcas académicas:** Referencias a "grupo 9" y entregas universitarias que deben ser sanitizadas para publicar un caso de ingeniería impecable.

---

## 2. Estructura de Destino del Repositorio

```text
postgresql-business-rules/
├── README.md                       # Documentación ejecutiva, DER y guía de uso rápido
├── LICENSE                         # Licencia MIT
├── Makefile                        # Orquestador: make up, make down, make reset, make test
├── docker-compose.yml              # PostgreSQL 16 Alpine con btree_gist
├── .gitignore                      # Exclusiones seguras
├── PLAN-EJECUCION-FASES.md         # Este documento maestro de trazabilidad
│
├── docs/
│   ├── modelo-conceptual.md        # Entidades, dominios, cardinalidades y diccionario
│   ├── reglas-de-negocio.md        # Matriz: Regla -> Objeto SQL -> Protección -> Prueba
│   ├── decisiones-tecnicas.md      # ADRs (GiST vs triggers, 3FN, solución overbooking)
│   ├── bugs-encontrados.md         # Defectos detectados por la batería: causa raíz y corrección
│   └── migracion-del-modelo.md     # Bitácora de refactorización desde el modelo original
│
├── diagramas/
│   ├── der.puml                    # Código fuente PlantUML del Modelo Entidad-Relación
│   ├── der.png                     # Render gráfico de alta resolución para el README
│   └── flujo-reglas.puml           # Diagrama de secuencia/flujo de validación en motor
│
├── sql/
│   ├── 01-schema.sql               # Extensiones, tipos, dominios, tablas 3FN, PK/FK, CHECK y GiST
│   ├── 02-functions.sql            # Funciones PL/pgSQL con SECURITY INVOKER y control de excepciones
│   ├── 03-triggers.sql             # Triggers documentados vinculados a eventos del ciclo de vida
│   ├── 04-seed.sql                 # Datos sintéticos idempotentes y coherentes
│   └── 99-drop.sql                 # Script de limpieza limpia en cascada inversa
│
├── tests/
│   ├── 00-helpers.sql              # Micro-framework de aserciones (pg_temp), incluido por cada suite
│   ├── 01-casos-positivos.sql      # Inserciones y flujos normales válidos
│   ├── 02-casos-negativos.sql      # Intentos de transacciones inválidas con aserción de ERRCODE
│   └── 03-concurrencia.sql         # Simulación de condiciones de carrera y venta simultánea
│
└── scripts/
    ├── init-db.sh                  # Inicialización automatizada del contenedor
    ├── reset-db.sh                 # Limpieza y recarga en caliente
    └── run-tests.sh                # Ejecutor de batería de pruebas con reporte coloreado
```

---

## 3. Fases de Desarrollo

### Fase 0: Inicialización del Laboratorio y Preservación del Origen
- [x] Crear estructura de directorios (`sql/`, `docs/`, `diagramas/`, `tests/`, `scripts/`).
- [x] Crear `.gitignore` profesional (ignorar dumps temporales, `.DS_Store`, etc.).
- [x] Crear `docs/migracion-del-modelo.md` documentando el inventario de partida y las transformaciones planeadas.
- [x] Mantener intactos los archivos base originales en la raíz (`sql ddl`, `sql insert`, `sql consultas`, `backup`, `modelo conceptual.drawio`, etc.) durante el proceso de migración.

### Fase 1: DDL Normalizado y Restricciones Declarativas (3FN)
- [x] Crear `sql/01-schema.sql`:
  - Habilitar extensión `btree_gist`.
  - Crear tipos enumerados (`tipo_empleado`, `tipo_sala`, `clasificacion_pelicula`, `tipo_publicidad`, `tipo_entrada`).
  - Crear dominios con validaciones regex (`email`, `ean13`).
  - Normalizar entidades principales:
    - `sucursal`: datos de sede y contacto.
    - `empleado`: legajo PK, DNI único, FK sucursal, índice parcial para gerente único por sucursal (`UNIQUE (id_sucursal) WHERE empleado = 'gerente'`).
    - `sala`: vinculada a sucursal, capacidad y tecnología (`tipo_sala`).
    - `kiosko`: un solo kiosko por sucursal (`UNIQUE (id_sucursal)`).
    - `articulo`: precios monetarios en `numeric(10,2)`.
    - `pelicula`: duraciones en minutos enteros (`integer`) o intervalos consistentes.
    - `publicidad`: duración y clasificación.
    - `espacio_publicitario`: duración acumulada y clasificación restrictiva.
    - `cartelera`: vinculada a `id_sucursal` con vigencia temporal (`fecha_inicio`, `fecha_fin`).
    - `funcion`: identificada por `id_funcion`, combinando película, cartelera, espacio publicitario, formato, idioma y fecha/hora de inicio.
    - `proyeccion`: tabla de asignación física `(nro_sala, id_funcion)` con `rango_ocupacion tstzrange` y restricción `EXCLUDE USING gist (nro_sala WITH =, rango_ocupacion WITH &&)`.
    - `entrada`: asociada a la proyección concreta `(nro_sala, id_funcion)` con restricción `UNIQUE (nro_sala, id_funcion, nro_asiento)` para evitar overbooking.
- [x] Crear `sql/99-drop.sql` para borrado limpio en orden inverso de dependencias.
- [x] Fijar la zona horaria operativa `America/Argentina/Buenos_Aires` a nivel base de datos (`ALTER DATABASE ... SET timezone`), revertida en `99-drop.sql`. Los `timestamptz` se siguen almacenando en UTC; la zona solo define la interpretación de literales sin offset y la presentación.

### Fase 2: Lógica Procedural y Triggers PL/pgSQL
- [x] Crear `sql/02-functions.sql`:
  - `fn_calcular_fin_funcion()`: calcula `fecha_hora_fin` sumando duración de película, espacio publicitario y tiempo técnico de limpieza (20 min).
  - `fn_validar_compatibilidad_sala()`: valida que proyecciones 3D/IMAX solo se asignen a salas con equipamiento equivalente.
  - `fn_validar_sucursal_proyeccion()`: asegura que la sala física pertenezca a la misma sucursal que la cartelera de la función.
  - `fn_validar_numero_asiento()`: valida que el asiento solicitado exista dentro de la capacidad física de la sala asignada.
  - `fn_recalcular_espacio_publicitario()`: actualiza dinámicamente duración y clasificación ante `INSERT`, `UPDATE` o `DELETE` en `compone`.
  - `fn_validar_clasificacion_espacio_pelicula()`: comprueba que el espacio publicitario no tenga una clasificación superior a la de la película.
- [x] Crear `sql/03-triggers.sql` vinculando cada función a su evento correspondiente con convenciones estrictas y `SECURITY INVOKER`.
- [x] Correcciones detectadas durante la Fase 4 (cubiertas por tests de regresión):
  - `trg_funcion_propagar_horario` pasa de `UPDATE OF fecha_hora_inicio, fecha_hora_fin` a `WHEN (OLD ... IS DISTINCT FROM NEW ...)`. `UPDATE OF` solo considera las columnas del `SET`, por lo que un cambio de película recalculaba `fecha_hora_fin` sin actualizar `proyeccion.rango_ocupacion`, y la exclusión GiST no detectaba el solapamiento resultante (tests P-11, N-05).
  - Nuevo `fn_propagar_espacio_a_funciones()` + `trg_espacio_propagar_a_funciones`: al cambiar la duración o la clasificación de un espacio publicitario en uso, se revalidan el horario, la clasificación y el solapamiento de sus funciones (tests P-14, N-06, N-17).
  - `trg_funcion_calcular_fin` se dispara ante cualquier `UPDATE` y `trg_proyeccion_sincronizar_rango` ante `INSERT OR UPDATE`, siempre derivando: `fecha_hora_fin`, `duracion_total_min` y `rango_ocupacion` dejan de ser editables a mano (test P-12).

### Fase 3: Seed de Datos Coherente y Relacional
- [x] Crear `sql/04-seed.sql`:
  - Poblar sucursales reales ficticias.
  - Asignar empleados, roles y gerentes únicos.
  - Poblar salas con capacidades y tipos diferenciados.
  - Configurar películas de diversos géneros y clasificaciones.
  - Configurar publicidades y componer espacios publicitarios balanceados.
  - Programar carteleras y funciones que demuestren proyecciones simultáneas válidas y consecutivas.
  - Registrar ventas de entradas ordinarias.
- [x] Sincronizar la secuencia identity de `espacio_publicitario` tras la carga con `OVERRIDING SYSTEM VALUE` (sin esto, la siguiente alta colisionaba con la PK; test P-13).

### Fase 4: Batería de Pruebas Automatizadas
- [x] Crear `tests/00-helpers.sql`: micro-framework de aserciones en `pg_temp` (`assert_true`, `assert_igual`, `assert_acepta`, `assert_rechaza`, `sqlstate_de`, `resumen`). `assert_rechaza` verifica el SQLSTATE exacto y un fragmento del mensaje (varias reglas comparten `23514`), y siempre revierte la sentencia para que un fallo no contamine las pruebas siguientes. `resumen` aborta si hay fallas: psql termina con código ≠ 0.
- [x] Crear `tests/01-casos-positivos.sql` — **30 aserciones**: zona horaria, cálculo de fin, espacios publicitarios, simultaneidad entre salas, multi-sala, funciones consecutivas, contigüidad `[)`, 2D en sala 3D, cruce de medianoche, propagación de horario/película/espacio a las proyecciones, atributos derivados no editables, recálculo en `compone` (INSERT/UPDATE/DELETE), asiento en el límite de capacidad y cartelera publicable.
- [x] Crear `tests/02-casos-negativos.sql` — **29 aserciones** con SQLSTATE exacto:
  - Solapamiento `23P01`: misma sala, 1 minuto, cruce de medianoche, provocado por UPDATE de horario, por cambio de película y por alargar el espacio publicitario.
  - Overbooking: doble venta `23505`, asiento fuera de capacidad / asiento 0 / precio negativo `23514`, proyección inexistente `23503`.
  - Tecnología de sala `23514`: 3D en 2D, IMAX en 3D, reasignación por UPDATE.
  - Clasificación etaria `23514`: por INSERT, por UPDATE de espacio, por alta en `compone`, por cambio de película.
  - Sucursal `23503`, segundo gerente / segundo kiosko `23505`, cartelera solapada `23P01` / fechas invertidas `23514` / no publicable `23514`, dominios `email` y `ean13` `23514`, borrados con dependencias `23503`.
- [x] Crear `tests/03-concurrencia.sql` — **9 aserciones** con dos sesiones reales vía `dblink`: se verifica que la sesión B queda bloqueada (`pg_stat_activity.wait_event_type = 'Lock'`) mientras A no confirma. Casos: doble venta simultánea (B recibe `23505`), A revierte (B completa la venta) y programación simultánea solapada en la misma sala (B recibe `23P01` por la exclusión GiST). Limpia sus datos y desinstala `dblink` al terminar.
- [x] Prueba de mutación: con los triggers anteriores a las correcciones, fallan exactamente P-11, P-14, N-05, N-06 y N-17, y psql sale con código 3.

- [x] Documentar los bugs detectados, su causa raíz y su corrección en `docs/bugs-encontrados.md`.

> **Ejecución:** `make test`. 01 y 02 no modifican datos; 03 confirma datos reales pero los elimina al terminar.

### Fase 5: Dockerización y Automatización Local
- [x] Crear `docker-compose.yml` con imagen `postgres:16-alpine`:
  - Base `sunstar`, puerto `127.0.0.1:5433` (evita chocar con un PostgreSQL local en 5432). Credenciales y puerto se pueden sobrescribir con `.env` (`POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_PORT`).
  - Volumen con nombre `pgdata`; `sql/`, `tests/` y `scripts/` montados de solo lectura en `/lab`.
  - El healthcheck usa `pg_isready` **por TCP**: durante la inicialización el servidor temporal solo escucha por socket, así que el contenedor queda `healthy` recién cuando terminó de cargar el seed. Así `up --wait` no devuelve el control antes de tiempo.
  - Sin `TZ`/`PGTZ`: la zona horaria queda fijada en la base por `01-schema.sql`.
- [x] Crear `Makefile`: `help` (por defecto), `up` (`up -d --wait`), `down`, `reset`, `test` (`SUITES="02 03"` para elegir, `NO_COLOR=1`), `psql`, `logs`, `clean` (`down -v`).
- [x] Crear `scripts/init-db.sh` (carga 01–04 en la primera inicialización), `scripts/reset-db.sh` (99-drop + 01–04) y `scripts/run-tests.sh` (reset + suites coloreadas, código ≠ 0 si alguna falla, código 2 si la suite pedida no existe). Todos corren dentro del contenedor: el host solo necesita Docker y `make`.
- [x] Verificado: `make clean && make up` en 5,3 s; `make test` completo (reset + 68 aserciones) en 2,6 s; `down`/`up` conserva los datos; con los triggers originales el runner reporta las suites con fallas y sale con código 1.

### Fase 6: Documentación Técnica, Diagramas y Sanitización

**Diagramas**
- [ ] Crear `diagramas/der.puml` con el modelo relacional final (22 tablas), incluyendo `proyeccion` como asociación física función–sala y `entrada → proyeccion` por FK compuesta.
- [ ] Generar imagen `diagramas/der.png`.
- [ ] Crear `diagramas/flujo-reglas.puml`: cadena de triggers `compone → espacio_publicitario → funcion → proyeccion → EXCLUDE gist`, que es la que resolvió los bugs de propagación.

**Documentación**
- [ ] Redactar `docs/modelo-conceptual.md` (entidades, dominios, cardinalidades, diccionario).
- [ ] Redactar `docs/reglas-de-negocio.md`: matriz Regla → Objeto SQL → SQLSTATE → Tests (P-xx / N-xx / C-xx). Los IDs de prueba ya están definidos en `tests/`.
- [ ] Redactar `docs/decisiones-tecnicas.md` con ADRs:
  - GiST `EXCLUDE` vs trigger de validación (el trigger no protege bajo concurrencia; demostrado en C-03).
  - Rangos semiabiertos `[)` (contigüidad permitida: P-07 vs N-02).
  - `timestamptz` + zona horaria fijada en la base vs `TIME` (cruce de medianoche: P-09, N-03).
  - Atributos derivados no editables (`fecha_hora_fin`, `rango_ocupacion`).
  - `WHEN (OLD IS DISTINCT FROM NEW)` vs `UPDATE OF`: los triggers BEFORE modifican columnas que `UPDATE OF` no ve.
  - Propagación en cascada con un UPDATE no-op (`SET cod_espacio = cod_espacio`) para reutilizar las validaciones existentes.
  - SQLSTATE estándar en `RAISE` (`23514`, `23503`) + fragmento de mensaje para distinguir reglas.
  - `dblink` para probar concurrencia real en SQL puro.
- [ ] Corregir `docs/migracion-del-modelo.md`, que quedó desalineado con la implementación:
  - Menciona `publicar_cartelera()`; la función real es `fn_validar_cartelera_publicable(integer)`.
  - Menciona el índice `sucursal_gerente_unico_idx`; el real es `empleado_gerente_por_sucursal_uidx`.
  - Dice que `sql consultas` "se integran como vistas operativas"; todavía no existen. Decidir entre crear `sql/05-vistas.sql` o quitar la mención.
  - Agregar las correcciones de la Fase 4 (propagación y atributos derivados).
- [ ] Redactar `README.md` final: tesis, DER, matriz de reglas, snippets clave (EXCLUDE gist, trigger de fin, cadena de propagación), quickstart (`make up && make test`) y salida de ejemplo de la batería (68 aserciones).

**Portafolio** (`/home/micaela/cuaderno/emprendimiento/portafolio/caso-03-modelo-logica-bd-postgresql.md`)
- [ ] Unificar la numeración: el archivo es `caso-03` pero el título dice "Caso 2" (igual que este plan).
- [ ] Unificar el nombre del repo: el documento usa `diseno-reglas-negocio-postgresql`; el remoto real es `postgresql-business-rules`.
- [ ] Actualizar el DER y los snippets al modelo implementado: `ticket`/`butaca` → `entrada` (asiento como número validado contra `sala.cant_asientos`); `rango_ocupacion` derivado por trigger; `fn_calcular_fin_funcion` suma también el espacio publicitario; columnas `codigo_pelicula`/`codigo_cartelera`.
- [ ] Actualizar la estructura de repositorio (agregar `tests/00-helpers.sql`, `tests/03-concurrencia.sql`, `docs/migracion-del-modelo.md`, `scripts/reset-db.sh`).

**Sanitización y publicación**
- [ ] ⚠️ El PDF `Trabajo Practico Integrador - grupo  9.pdf`, `backup`, `sql ddl`, `sql insert`, `sql consultas` y `modelo conceptual.drawio` están en el commit `4a939d5`, **ya pusheado a `origin/main`**. Borrarlos en un commit nuevo no los saca del historial. Opciones:
  1. Reescribir el historial (`git filter-repo --path ... --invert-paths`) y hacer `push --force`.
  2. Recrear el repositorio con un historial limpio (más simple, dado que hay solo 2 commits).
- [ ] Revisados los originales: solo el PDF contiene marcas académicas ("grupo 9"). `backup`, el `.drawio` y los `sql *` no tienen nombres de docentes ni materias, pero son redundantes con `sql/` y se retiran para dejar el repo limpio (el `.drawio` se reemplaza por `diagramas/der.puml`).
- [x] `PLAN-DESARROLLO-CASO-3.md` eliminado del working tree (falta commitear el borrado).
- [ ] Decidir si `PLAN-EJECUCION-FASES.md` queda en el repo público o se mueve al cuaderno (su sección de diagnóstico menciona "grupo 9").

---

## 4. Criterio de Aceptación (Definición de Terminado)

El Caso 2 se considera completado y listo para vincular en el portafolio cuando:
1. `docker compose up -d` inicie PostgreSQL 16 sin intervención manual.
2. `make reset` ejecute en orden `01-schema.sql`, `02-functions.sql`, `03-triggers.sql` y `04-seed.sql` sin errores ni advertencias.
3. `make test` ejecute todas las pruebas positivas y negativas, verificando que los errores rechazados capturen exactamente los `ERRCODE` esperados.
4. El repositorio no contenga ningún rastro de nombres de docentes ni referencias a trabajos prácticos universitarios.
5. El `README.md` exponga el DER visual, la tesis técnica, la matriz de reglas y los snippets de código clave.

