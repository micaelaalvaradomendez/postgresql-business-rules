-- ============================================================================
-- PROYECTO: Automatización e Integridad Transaccional en PostgreSQL
-- CASO: Cadena de Cines Sunstar — Motor Relacional y Reglas de Negocio
-- ARCHIVO: tests/03-concurrencia.sql
-- DESCRIPCIÓN: Condiciones de carrera reales entre dos sesiones concurrentes
--              (sesion_a y sesion_b), abiertas con dblink sobre la misma base.
--
--   1. sesion_a abre una transacción y escribe, sin confirmar.
--   2. sesion_b intenta la escritura conflictiva de forma asíncrona.
--   3. Se verifica que sesion_b queda BLOQUEADA esperando a sesion_a:
--      el motor serializa el conflicto sin locks explícitos de aplicación.
--   4. sesion_a confirma (o revierte) y se observa el resultado de sesion_b.
--
-- PRECONDICIÓN: base recién cargada con sql/01..04 (seed intacto). Requiere
--               que el usuario actual pueda conectarse por socket local sin
--               contraseña (configuración por defecto de la imagen Docker).
-- EFECTOS: las sesiones remotas confirman datos reales; la suite los elimina
--          al comenzar y al terminar, y desinstala dblink.
-- ============================================================================

\ir 00-helpers.sql

CREATE EXTENSION IF NOT EXISTS dblink;

-- ----------------------------------------------------------------------------
-- Helpers específicos de concurrencia
-- ----------------------------------------------------------------------------

-- Espera (máx. 5 s) a que el backend indicado quede bloqueado por un lock
CREATE FUNCTION pg_temp.esperar_bloqueo(p_pid integer)
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
    FOR i IN 1..50 LOOP
        IF EXISTS (SELECT 1 FROM pg_stat_activity
                   WHERE pid = p_pid AND wait_event_type = 'Lock') THEN
            RETURN true;
        END IF;
        PERFORM pg_sleep(0.1);
    END LOOP;
    RETURN false;
END;
$$;

-- Recoge el resultado de una consulta asíncrona y devuelve su SQLSTATE
-- ('00000' si fue aceptada). dblink propaga el SQLSTATE de la sesión remota.
CREATE FUNCTION pg_temp.sqlstate_remoto(p_conexion text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado text := '00000';
BEGIN
    BEGIN
        PERFORM * FROM dblink_get_result(p_conexion) AS t(estado text);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_estado = RETURNED_SQLSTATE;
    END;
    -- Consumir el resultado vacío final que deja libre la conexión
    PERFORM * FROM dblink_get_result(p_conexion) AS t(estado text);
    RETURN v_estado;
END;
$$;

-- Limpieza idempotente de corridas anteriores
CREATE FUNCTION pg_temp.limpiar()
RETURNS void
LANGUAGE sql
AS $$
    DELETE FROM entrada WHERE (nro_sala, id_funcion) = (1, 1) AND nro_asiento IN (100, 101);
    DELETE FROM funcion WHERE idioma LIKE 'TEST-C%';
$$;

SELECT pg_temp.limpiar();

-- ----------------------------------------------------------------------------
-- Apertura de las dos sesiones concurrentes
-- ----------------------------------------------------------------------------
SELECT dblink_connect('sesion_a', format('dbname=%s user=%s', current_database(), current_user));
SELECT dblink_connect('sesion_b', format('dbname=%s user=%s', current_database(), current_user));

SELECT pid AS pid_b FROM dblink('sesion_b', 'SELECT pg_backend_pid()') AS t(pid integer)
\gset

-- ============================================================================
-- C-01 Venta simultánea del mismo asiento: gana quien confirma primero
-- ============================================================================
SELECT dblink_exec('sesion_a', 'BEGIN');
SELECT dblink_exec('sesion_a',
    $$INSERT INTO entrada (nro_sala, id_funcion, nro_asiento, tipo_entrada, precio)
      VALUES (1, 1, 100, 'online', 5500.00)$$);

SELECT dblink_send_query('sesion_b',
    $$INSERT INTO entrada (nro_sala, id_funcion, nro_asiento, tipo_entrada, precio)
      VALUES (1, 1, 100, 'kiosko', 5000.00)$$);

SELECT pg_temp.assert_true(
    'C-01 La venta de B queda bloqueada mientras A no confirma',
    pg_temp.esperar_bloqueo(:pid_b));

SELECT dblink_exec('sesion_a', 'COMMIT');

SELECT pg_temp.assert_igual(
    'C-01 Al confirmar A, la venta de B es rechazada (unique_violation)',
    pg_temp.sqlstate_remoto('sesion_b'), '23505');

SELECT pg_temp.assert_igual(
    'C-01 El asiento 100 quedó vendido exactamente una vez',
    (SELECT count(*) FROM entrada WHERE (nro_sala, id_funcion, nro_asiento) = (1, 1, 100)), 1::bigint);

-- ============================================================================
-- C-02 Si A revierte, B no se rechaza: completa la venta tras la espera
-- ============================================================================
SELECT dblink_exec('sesion_a', 'BEGIN');
SELECT dblink_exec('sesion_a',
    $$INSERT INTO entrada (nro_sala, id_funcion, nro_asiento, tipo_entrada, precio)
      VALUES (1, 1, 101, 'online', 5500.00)$$);

SELECT dblink_send_query('sesion_b',
    $$INSERT INTO entrada (nro_sala, id_funcion, nro_asiento, tipo_entrada, precio)
      VALUES (1, 1, 101, 'kiosko', 5000.00)$$);

SELECT pg_temp.assert_true(
    'C-02 La venta de B queda bloqueada mientras A no decide',
    pg_temp.esperar_bloqueo(:pid_b));

SELECT dblink_exec('sesion_a', 'ROLLBACK');

SELECT pg_temp.assert_igual(
    'C-02 Al revertir A, la venta de B se acepta',
    pg_temp.sqlstate_remoto('sesion_b'), '00000');

SELECT pg_temp.assert_igual(
    'C-02 El asiento 101 pertenece a la venta de B (kiosko)',
    (SELECT string_agg(tipo_entrada::text, ',') FROM entrada
     WHERE (nro_sala, id_funcion, nro_asiento) = (1, 1, 101)), 'kiosko');

-- ============================================================================
-- C-03 Programación simultánea de funciones solapadas en la misma sala
-- ============================================================================
-- Dos funciones confirmadas y sin sala: 21:00–23:00 y 21:30–23:30.
-- La Sala 2 está libre desde las 19:40.
INSERT INTO funcion (codigo_pelicula, codigo_cartelera, tipo_pelicula, idioma, fecha_hora_inicio)
VALUES
    (1, 1, '2D', 'TEST-C03a', '2026-10-15 21:00-03'),
    (1, 1, '2D', 'TEST-C03b', '2026-10-15 21:30-03');

SELECT dblink_exec('sesion_a', 'BEGIN');
SELECT dblink_exec('sesion_a',
    $$INSERT INTO proyeccion (nro_sala, id_funcion)
      VALUES (2, (SELECT id_funcion FROM funcion WHERE idioma = 'TEST-C03a'))$$);

SELECT dblink_send_query('sesion_b',
    $$INSERT INTO proyeccion (nro_sala, id_funcion)
      VALUES (2, (SELECT id_funcion FROM funcion WHERE idioma = 'TEST-C03b'))$$);

SELECT pg_temp.assert_true(
    'C-03 La programación de B queda bloqueada por la exclusión GiST',
    pg_temp.esperar_bloqueo(:pid_b));

SELECT dblink_exec('sesion_a', 'COMMIT');

SELECT pg_temp.assert_igual(
    'C-03 Al confirmar A, B es rechazada (exclusion_violation)',
    pg_temp.sqlstate_remoto('sesion_b'), '23P01');

SELECT pg_temp.assert_igual(
    'C-03 La Sala 2 tiene una sola de las dos funciones solapadas',
    (SELECT count(*) FROM proyeccion p JOIN funcion f USING (id_funcion)
     WHERE p.nro_sala = 2 AND f.idioma LIKE 'TEST-C03%'), 1::bigint);

-- ----------------------------------------------------------------------------
-- Cierre y limpieza
-- ----------------------------------------------------------------------------
SELECT dblink_disconnect('sesion_a');
SELECT dblink_disconnect('sesion_b');
SELECT pg_temp.limpiar();
DROP EXTENSION dblink;

-- ----------------------------------------------------------------------------
-- Resultados
-- ----------------------------------------------------------------------------
\o
:listar_resultados
SELECT pg_temp.resumen('03-concurrencia') AS resumen;
