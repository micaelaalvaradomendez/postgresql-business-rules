-- ============================================================================
-- PROYECTO: Automatización e Integridad Transaccional en PostgreSQL
-- CASO: Cadena de Cines Sunstar — Motor Relacional y Reglas de Negocio
-- ARCHIVO: tests/00-helpers.sql
-- DESCRIPCIÓN: Micro-framework de aserciones en PL/pgSQL. No es una suite:
--              cada archivo de pruebas lo incluye con \ir 00-helpers.sql.
--              Las funciones viven en pg_temp y desaparecen al cerrar la sesión.
-- ============================================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset footer off
SET client_min_messages = warning;

CREATE TEMP TABLE resultado_test (
    nro      serial PRIMARY KEY,
    prueba   text    NOT NULL,
    ok       boolean NOT NULL,
    detalle  text
);

-- ----------------------------------------------------------------------------
-- Registro de un resultado
-- ----------------------------------------------------------------------------
CREATE FUNCTION pg_temp.registrar(p_prueba text, p_ok boolean, p_detalle text DEFAULT NULL)
RETURNS void
LANGUAGE sql
AS $$
    INSERT INTO resultado_test (prueba, ok, detalle) VALUES (p_prueba, p_ok, p_detalle);
$$;

-- ----------------------------------------------------------------------------
-- Aserción booleana
-- ----------------------------------------------------------------------------
CREATE FUNCTION pg_temp.assert_true(p_prueba text, p_condicion boolean, p_detalle text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM pg_temp.registrar(p_prueba, coalesce(p_condicion, false), p_detalle);
END;
$$;

-- ----------------------------------------------------------------------------
-- Aserción de igualdad (informa obtenido vs esperado si falla)
-- ----------------------------------------------------------------------------
CREATE FUNCTION pg_temp.assert_igual(p_prueba text, p_obtenido anycompatible, p_esperado anycompatible)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_obtenido IS NOT DISTINCT FROM p_esperado THEN
        PERFORM pg_temp.registrar(p_prueba, true, format('= %s', p_esperado));
    ELSE
        PERFORM pg_temp.registrar(p_prueba, false,
                                  format('obtenido %s, esperado %s', p_obtenido, p_esperado));
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- Aserción de aceptación: la sentencia debe ejecutarse sin error
-- ----------------------------------------------------------------------------
CREATE FUNCTION pg_temp.assert_acepta(p_prueba text, p_sql text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado  text;
    v_mensaje text;
BEGIN
    EXECUTE p_sql;
    PERFORM pg_temp.registrar(p_prueba, true, 'aceptada');
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_estado = RETURNED_SQLSTATE, v_mensaje = MESSAGE_TEXT;
    PERFORM pg_temp.registrar(p_prueba, false, format('rechazada [%s] %s', v_estado, v_mensaje));
END;
$$;

-- ----------------------------------------------------------------------------
-- Ejecuta una sentencia y devuelve su SQLSTATE ('00000' si fue aceptada).
-- Útil dentro de un SAVEPOINT: el resultado se captura con \gset y se afirma
-- después del ROLLBACK TO SAVEPOINT, que revertiría el registro en resultado_test.
-- ----------------------------------------------------------------------------
CREATE FUNCTION pg_temp.sqlstate_de(p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado text;
BEGIN
    EXECUTE p_sql;
    RETURN '00000';
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_estado = RETURNED_SQLSTATE;
    RETURN v_estado;
END;
$$;

-- ----------------------------------------------------------------------------
-- Aserción de rechazo: la sentencia debe fallar con el SQLSTATE esperado y,
-- opcionalmente, con un fragmento de mensaje que identifique la regla violada
-- (varias reglas comparten SQLSTATE 23514 check_violation).
-- La sentencia se revierte SIEMPRE, incluso si fue aceptada por error (se
-- fuerza la excepción centinela TSTOK), para que un rechazo que no ocurrió no
-- contamine el estado de las pruebas siguientes.
-- ----------------------------------------------------------------------------
CREATE FUNCTION pg_temp.assert_rechaza(p_prueba text, p_sql text, p_sqlstate text, p_fragmento text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado  text;
    v_mensaje text;
BEGIN
    BEGIN
        EXECUTE p_sql;
        RAISE EXCEPTION USING ERRCODE = 'TSTOK', MESSAGE = 'sentencia aceptada';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_estado = RETURNED_SQLSTATE, v_mensaje = MESSAGE_TEXT;
    END;

    IF v_estado = 'TSTOK' THEN
        PERFORM pg_temp.registrar(p_prueba, false,
                                  format('aceptada; se esperaba SQLSTATE %s', p_sqlstate));
    ELSIF v_estado <> p_sqlstate THEN
        PERFORM pg_temp.registrar(p_prueba, false,
                                  format('SQLSTATE %s (%s); se esperaba %s', v_estado, v_mensaje, p_sqlstate));
    ELSIF p_fragmento IS NOT NULL AND strpos(v_mensaje, p_fragmento) = 0 THEN
        PERFORM pg_temp.registrar(p_prueba, false,
                                  format('SQLSTATE correcto pero mensaje inesperado: %s', v_mensaje));
    ELSE
        PERFORM pg_temp.registrar(p_prueba, true, format('rechazada [%s]', v_estado));
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- Resumen de la suite: lista resultados y aborta con error si alguno falló,
-- para que psql (ON_ERROR_STOP) termine con código de salida distinto de 0.
-- ----------------------------------------------------------------------------
CREATE FUNCTION pg_temp.resumen(p_suite text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_total  integer;
    v_fallas integer;
BEGIN
    SELECT count(*), count(*) FILTER (WHERE NOT ok) INTO v_total, v_fallas FROM resultado_test;

    IF v_fallas > 0 THEN
        RAISE EXCEPTION '% — % de % pruebas FALLARON', p_suite, v_fallas, v_total;
    END IF;

    RETURN format('%s — %s de %s pruebas OK', p_suite, v_total, v_total);
END;
$$;

-- Listado de resultados, invocable desde cada suite como :listar_resultados
\set listar_resultados 'SELECT nro AS "#", CASE WHEN ok THEN ''PASS'' ELSE ''FAIL'' END AS resultado, prueba, detalle FROM resultado_test ORDER BY nro;'

-- Se silencia la salida de cada aserción; cada suite la restaura con \o
-- antes de listar los resultados. Los errores siguen saliendo por stderr.
\o /dev/null
