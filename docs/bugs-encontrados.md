# Bugs encontrados por la batería de pruebas

Este documento registra los defectos que la batería de pruebas (Fase 4) detectó en el esquema, las funciones y el seed, cómo se reprodujeron, cuál era la causa raíz y cómo se corrigieron. Cada corrección quedó protegida por pruebas de regresión en `tests/`.

Ninguno de estos defectos producía errores visibles: el motor **aceptaba** datos que violaban reglas de negocio. Por eso solo aparecieron al escribir pruebas que intentaban romper las reglas por caminos indirectos, en lugar de validar únicamente el camino directo.

| # | Defecto | Severidad | Regla afectada | Pruebas de regresión |
|---|---|---|---|---|
| 1 | Cambiar la película de una función no actualizaba el rango de ocupación de la sala | **Alta** | R-01 No solapamiento | P-11, N-05 |
| 2 | Modificar un espacio publicitario en uso no revalidaba sus funciones | **Alta** | R-01, R-03, R-05 | P-14, N-06, N-17 |
| 3 | Atributos derivados editables manualmente | Media | R-01, R-03 | P-12 |
| 4 | Secuencia identity de `espacio_publicitario` desincronizada tras el seed | Media | — (operativa) | P-13 |

---

## Bug 1 — Solapamiento no detectado al cambiar la película de una función

### Síntoma
Al cambiar la película de una función ya asignada a una sala, `funcion.fecha_hora_fin` se recalculaba correctamente, pero `proyeccion.rango_ocupacion` conservaba el horario anterior. La restricción de exclusión GiST evalúa `rango_ocupacion`, así que un solapamiento real entre funciones de la **misma sala** pasaba inadvertido.

### Reproducción
```sql
-- F1: Toy Story (100 min) en Sala 1, 14:00–16:04. F4 empieza a las 17:00 en la misma sala.
UPDATE funcion SET codigo_pelicula = 4 WHERE id_funcion = 1;   -- Oppenheimer, 180 min

SELECT f.fecha_hora_fin, p.rango_ocupacion
FROM funcion f JOIN proyeccion p USING (id_funcion)
WHERE id_funcion = 1;
--      fecha_hora_fin     |                   rango_ocupacion
-- ------------------------+-----------------------------------------------------
--  2026-10-15 17:24:00-03 | ["2026-10-15 14:00:00-03","2026-10-15 16:04:00-03")
```
La función termina a las 17:24 pero la sala figura libre desde las 16:04: F1 y F4 se superponen 24 minutos en la Sala 1 y el UPDATE se acepta.

### Causa raíz
El trigger que propaga el horario hacia `proyeccion` estaba declarado como:
```sql
AFTER UPDATE OF fecha_hora_inicio, fecha_hora_fin ON funcion
```
En PostgreSQL, `UPDATE OF columna` se dispara solo si la columna aparece en la lista `SET` de la sentencia. **No considera las columnas modificadas por un trigger `BEFORE`.** Al ejecutar `SET codigo_pelicula = 4`, el trigger `BEFORE` `trg_funcion_calcular_fin` recalculaba `fecha_hora_fin`, pero como esa columna no estaba en el `SET`, el trigger de propagación nunca se disparaba.

Solo funcionaba el caso directo (`SET fecha_hora_inicio = ...`), que es el que se había probado.

### Solución
Se reemplazó `UPDATE OF` por una condición `WHEN` que compara los valores finales de la fila, después de los triggers `BEFORE` (`sql/03-triggers.sql`):
```sql
CREATE TRIGGER trg_funcion_propagar_horario
AFTER UPDATE
ON funcion
FOR EACH ROW
WHEN (OLD.fecha_hora_inicio IS DISTINCT FROM NEW.fecha_hora_inicio
      OR OLD.fecha_hora_fin IS DISTINCT FROM NEW.fecha_hora_fin)
EXECUTE FUNCTION fn_actualizar_rango_proyecciones_de_funcion();
```
Ahora la propagación ocurre sin importar qué columna originó el cambio de horario, y la exclusión GiST rechaza el solapamiento:
```
ERROR:  conflicting key value violates exclusion constraint "proyeccion_sin_solapamiento"
DETAIL:  Key (nro_sala, rango_ocupacion)=(1, ["2026-10-15 14:00:00-03","2026-10-15 17:24:00-03"))
         conflicts with existing key (nro_sala, rango_ocupacion)=(1, ["2026-10-15 17:00:00-03","2026-10-15 19:04:00-03")).
```

### Lección
En triggers `AFTER` que reaccionan a columnas derivadas, `UPDATE OF` es insuficiente cuando un trigger `BEFORE` puede modificarlas. `WHEN (OLD.col IS DISTINCT FROM NEW.col)` expresa la intención real: *"si el valor cambió"*, no *"si alguien escribió la columna"*.

---

## Bug 2 — Cambios en un espacio publicitario en uso no se revalidaban

### Síntoma
El espacio publicitario recalculaba su duración y clasificación al agregar o quitar piezas en `compone`, pero ese cambio no llegaba a las funciones que ya usaban el espacio. Esto rompía tres reglas a la vez:

- **R-05 (clasificación):** se podía agregar un trailer P-18 a un espacio que acompañaba películas ATP.
- **R-03 (horario de fin):** la duración del espacio aumentaba, pero `fecha_hora_fin` de las funciones no.
- **R-01 (solapamiento):** como el fin no cambiaba, tampoco se revalidaba la ocupación de las salas.

### Reproducción
```sql
-- El espacio 1 (ATP) acompaña a F1 y F4, ambas de Toy Story (ATP).
INSERT INTO compone (cod_espacio_publicitario, cod_publicidad) VALUES (1, 4);  -- trailer P-18

SELECT e.clasificacion AS espacio, pe.clasificacion AS pelicula, f.fecha_hora_fin
FROM funcion f
JOIN espacio_publicitario e USING (cod_espacio_publicitario)
JOIN pelicula pe USING (codigo_pelicula)
WHERE id_funcion = 1;
--  espacio | pelicula |     fecha_hora_fin
-- ---------+----------+------------------------
--  P-18    | ATP      | 2026-10-15 16:04:00-03
```
Se acepta un espacio P-18 en una película ATP y el horario de fin no incorpora los 160 segundos del trailer.

### Causa raíz
Las validaciones de clasificación y horario estaban definidas **solo sobre `funcion`** (`BEFORE INSERT OR UPDATE OF codigo_pelicula, cod_espacio_publicitario`). Solo se ejecutaban cuando se modificaba la función, no cuando se modificaba el espacio publicitario del que dependen. La cadena de dependencias `compone → espacio_publicitario → funcion → proyeccion` estaba cortada en el segundo eslabón.

### Solución
Se agregó una función y un trigger sobre `espacio_publicitario` que reasigna el mismo espacio a sus funciones mediante un UPDATE sin cambio de valor (`sql/02-functions.sql` y `sql/03-triggers.sql`):
```sql
CREATE OR REPLACE FUNCTION fn_propagar_espacio_a_funciones()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    UPDATE funcion
    SET cod_espacio_publicitario = NEW.cod_espacio_publicitario
    WHERE cod_espacio_publicitario = NEW.cod_espacio_publicitario;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_espacio_propagar_a_funciones
AFTER UPDATE OF duracion_seg, clasificacion
ON espacio_publicitario
FOR EACH ROW
WHEN (OLD.duracion_seg IS DISTINCT FROM NEW.duracion_seg
      OR OLD.clasificacion IS DISTINCT FROM NEW.clasificacion)
EXECUTE FUNCTION fn_propagar_espacio_a_funciones();
```
Como `cod_espacio_publicitario` aparece en el `SET`, ese UPDATE sin cambio de valor dispara en cadena **las validaciones que ya existían**, sin duplicar lógica:

1. `trg_funcion_calcular_fin` recalcula `fecha_hora_fin` con la nueva duración (R-03).
2. `trg_funcion_validar_clasificacion` rechaza la operación si el espacio quedó más restrictivo que la película (R-05).
3. `trg_funcion_propagar_horario` (corregido en el Bug 1) actualiza `proyeccion.rango_ocupacion`, y la exclusión GiST revalida el solapamiento (R-01).

Si cualquier eslabón falla, se revierte toda la sentencia original sobre `compone`:
```
ERROR:  Incompatibilidad etaria: El espacio publicitario 1 tiene clasificación P-18,
        que es más restrictiva que la película 1 (ATP)
```

### Lección
Una regla que depende de datos de otra tabla debe dispararse también cuando cambian **esos datos**, no solo cuando cambia la fila validada. Para no reescribir las validaciones, alcanza con que la tabla de origen reactive la cadena de triggers de la tabla dependiente.

---

## Bug 3 — Atributos derivados editables manualmente

### Síntoma
`funcion.fecha_hora_fin`, `funcion.duracion_total_min` y `proyeccion.rango_ocupacion` se calculan a partir de otros datos, pero se podían sobrescribir con cualquier valor. Un rango de ocupación falso deja sin efecto la exclusión GiST.

### Reproducción
```sql
UPDATE funcion SET fecha_hora_fin = '2026-10-15 14:05-03' WHERE id_funcion = 1;

SELECT fecha_hora_fin, duracion_total_min FROM funcion WHERE id_funcion = 1;
--      fecha_hora_fin     | duracion_total_min
-- ------------------------+--------------------
--  2026-10-15 14:05:00-03 |                124
```
Una función de 124 minutos queda registrada como de 5 minutos.

### Causa raíz
- `trg_funcion_calcular_fin` estaba declarado como `BEFORE INSERT OR UPDATE OF fecha_hora_inicio, codigo_pelicula, cod_espacio_publicitario`. Un UPDATE que solo tocaba `fecha_hora_fin` no lo disparaba.
- `fn_sincronizar_rango_proyeccion()` derivaba el rango solo si venía en `NULL` (`IF NEW.rango_ocupacion IS NULL`), y su trigger era solo `BEFORE INSERT`. Se aceptaba cualquier rango provisto al insertar o al actualizar.

### Solución
Los atributos derivados se recalculan **siempre**, sin importar lo que envíe el cliente:
```sql
-- sql/03-triggers.sql
CREATE TRIGGER trg_funcion_calcular_fin
BEFORE INSERT OR UPDATE            -- antes: UPDATE OF fecha_hora_inicio, codigo_pelicula, ...
ON funcion ...

CREATE TRIGGER trg_proyeccion_sincronizar_rango
BEFORE INSERT OR UPDATE            -- antes: solo BEFORE INSERT
ON proyeccion ...
```
```sql
-- sql/02-functions.sql — fn_sincronizar_rango_proyeccion()
-- antes: IF NEW.rango_ocupacion IS NULL THEN ... END IF;
SELECT fecha_hora_inicio, fecha_hora_fin INTO STRICT v_inicio, v_fin
FROM funcion WHERE id_funcion = NEW.id_funcion;

NEW.rango_ocupacion := tstzrange(v_inicio, v_fin, '[)');
```
Tras la corrección, el UPDATE de la reproducción se ejecuta pero `fecha_hora_fin` vuelve a quedar en 16:04.

### Lección
Un atributo derivado que el cliente puede sobrescribir no está derivado: es un valor por defecto. Si una restricción de integridad depende de él, como la exclusión GiST sobre `rango_ocupacion`, dejarlo editable anula la restricción.

---

## Bug 4 — Secuencia identity desincronizada en `espacio_publicitario`

### Síntoma
Después de cargar el seed, la primera alta de un espacio publicitario fallaba por clave primaria duplicada.

### Reproducción
```sql
INSERT INTO espacio_publicitario DEFAULT VALUES;
-- ERROR:  duplicate key value violates unique constraint "espacio_publicitario_pkey"
-- DETAIL:  Key (cod_espacio_publicitario)=(1) already exists.
```

### Causa raíz
El seed inserta los espacios 1, 2 y 3 con códigos explícitos mediante `OVERRIDING SYSTEM VALUE`, porque `compone` y `funcion` los referencian por número. Insertar valores explícitos en una columna `GENERATED ALWAYS AS IDENTITY` **no avanza su secuencia**: la siguiente alta automática vuelve a generar el código 1.

### Solución
Se sincroniza la secuencia inmediatamente después de la carga explícita (`sql/04-seed.sql`):
```sql
DO $$
BEGIN
    PERFORM setval(pg_get_serial_sequence('espacio_publicitario', 'cod_espacio_publicitario'),
                   (SELECT max(cod_espacio_publicitario) FROM espacio_publicitario));
END $$;
```

### Lección
Todo `OVERRIDING SYSTEM VALUE` (o `INSERT` con IDs explícitos sobre una columna `serial`) debe ir seguido de un `setval`. Es el mismo problema que aparece al restaurar datos o migrar entre bases.

---

## Cómo se verificaron las correcciones

1. **Reproducción previa:** cada bug se reprodujo con SQL mínimo contra el esquema original antes de modificarlo (los fragmentos de este documento).
2. **Pruebas de regresión:** cada corrección tiene al menos una prueba positiva (el cambio válido se propaga) y una negativa (el cambio inválido se rechaza con el SQLSTATE exacto).
3. **Prueba de mutación:** con las correcciones aplicadas, se reinstalaron en la base los triggers originales de los Bugs 1 y 2 y se ejecutó la batería. Fallaron exactamente las pruebas que cubren esos bugs, y psql terminó con código de salida 3:
   ```
   P-11  El rango de la Sala 3 refleja el nuevo fin              obtenido 16:52, esperado 17:10
   P-14  F1 y F4 extienden su fin en 1 minuto                    obtenido 16:04,19:04, esperado 16:05,19:05
   N-05  Cambiar F1 a Oppenheimer la extiende y choca con F4     aceptada; se esperaba SQLSTATE 23P01
   N-06  Alargar el espacio publicitario de F1 choca con F4      aceptada; se esperaba SQLSTATE 23P01
   N-17  Agregar un trailer P-18 al espacio de funciones ATP     aceptada; se esperaba SQLSTATE 23514
   ```
   Así se confirma que las pruebas detectan la regresión y no pasan por casualidad.

   Con el `sql/03-triggers.sql` original completo, ejecutado con `scripts/run-tests.sh`, fallan además las dos aserciones de P-12 (Bug 3), y el runner termina con código 1:
   ```
   ✘ Suites con fallas: 01-casos-positivos 02-casos-negativos
   ```
   Con el `sql/04-seed.sql` original, la reproducción del Bug 4 devuelve el `duplicate key` de arriba.

## Defectos de la propia batería de pruebas

La prueba de mutación también expuso dos problemas en los tests, que se corrigieron antes de darlos por válidos:

- **Dependencia del valor de una secuencia (P-13):** la prueba afirmaba que el nuevo espacio recibía el código 4. Como `ROLLBACK` no revierte secuencias, el valor dependía de cuántas veces se hubiera corrido la suite. Ahora afirma que el código supera los cargados por el seed (`> 3`).
- **Contaminación entre pruebas:** `assert_rechaza` revertía la sentencia solo cuando fallaba. Si una sentencia que debía rechazarse era aceptada (N-05), su efecto quedaba aplicado y alteraba las pruebas siguientes (N-16 pasaba a ser válida). Ahora la sentencia se revierte **siempre** con una excepción centinela (`TSTOK`), de modo que un fallo se reporta aislado.
