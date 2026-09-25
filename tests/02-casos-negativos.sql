-- ============================================================================
-- PROYECTO: Automatización e Integridad Transaccional en PostgreSQL
-- CASO: Cadena de Cines Sunstar — Motor Relacional y Reglas de Negocio
-- ARCHIVO: tests/02-casos-negativos.sql
-- DESCRIPCIÓN: Operaciones inválidas que el motor debe rechazar. Cada prueba
--              afirma el SQLSTATE exacto y, cuando varias reglas comparten
--              código (23514 check_violation), un fragmento del mensaje que
--              identifica la regla violada.
--
-- PRECONDICIÓN: base recién cargada con sql/01..04 (seed intacto).
-- EFECTOS: ninguno. La suite corre en una transacción que se revierte.
--
-- SQLSTATE esperados:
--   23P01 exclusion_violation     23505 unique_violation
--   23503 foreign_key_violation   23514 check_violation
--
-- Referencia del seed (sucursal Abasto, 15/10/2026, hora -03):
--   Sala 1 (2D, 120)  : F1 Toy Story 14:00–16:04 | F4 Toy Story 17:00–19:04 | F5 Oppenheimer 20:00–23:25
--   Sala 2 (3D, 150)  : F2 Dune 3D 16:30–19:40
--   Sala 3 (IMAX, 200): F3 Inception IMAX 14:00–16:52
--   Sala 4 (2D, 90)   : F4 Toy Story 17:00–19:04
--   Sala 5 (2D)       : sucursal Rosario (cartelera 2, sin funciones)
-- ============================================================================

\ir 00-helpers.sql

BEGIN;

-- ============================================================================
-- R-01 NO SOLAPAMIENTO EN SALAS FÍSICAS (EXCLUDE USING gist) → 23P01
-- ============================================================================

-- Funciones auxiliares sin sala asignada, identificadas por el campo idioma
INSERT INTO funcion (codigo_pelicula, codigo_cartelera, tipo_pelicula, idioma, fecha_hora_inicio)
VALUES
    (1, 1, '2D', 'TEST-N01', '2026-10-15 15:00-03'),  -- 15:00–17:00
    (1, 1, '2D', 'TEST-N02', '2026-10-15 19:39-03'),  -- 1 min antes de que termine F2
    (1, 1, '2D', 'TEST-N03a', '2026-10-15 23:30-03'), -- trasnoche 23:30–01:30
    (1, 1, '2D', 'TEST-N03b', '2026-10-16 01:00-03'); -- madrugada siguiente

INSERT INTO proyeccion (nro_sala, id_funcion)
VALUES (4, (SELECT id_funcion FROM funcion WHERE idioma = 'TEST-N03a'));

SELECT pg_temp.assert_rechaza(
    'N-01 Función solapada en la misma sala (15:00 en Sala 1 con F1 en curso)',
    $$INSERT INTO proyeccion (nro_sala, id_funcion)
      VALUES (1, (SELECT id_funcion FROM funcion WHERE idioma = 'TEST-N01'))$$,
    '23P01', 'proyeccion_sin_solapamiento');

SELECT pg_temp.assert_rechaza(
    'N-02 Solapamiento de 1 minuto (inicia 19:39, F2 termina 19:40 en Sala 2)',
    $$INSERT INTO proyeccion (nro_sala, id_funcion)
      VALUES (2, (SELECT id_funcion FROM funcion WHERE idioma = 'TEST-N02'))$$,
    '23P01', 'proyeccion_sin_solapamiento');

SELECT pg_temp.assert_rechaza(
    'N-03 Solapamiento cruzando la medianoche (01:00 del 16/10 en Sala 4)',
    $$INSERT INTO proyeccion (nro_sala, id_funcion)
      VALUES (4, (SELECT id_funcion FROM funcion WHERE idioma = 'TEST-N03b'))$$,
    '23P01', 'proyeccion_sin_solapamiento');

SELECT pg_temp.assert_rechaza(
    'N-04 Mover el horario de F4 a 15:30 choca con F1 en Sala 1',
    $$UPDATE funcion SET fecha_hora_inicio = '2026-10-15 15:30-03' WHERE id_funcion = 4$$,
    '23P01', 'proyeccion_sin_solapamiento');

SELECT pg_temp.assert_rechaza(
    'N-05 Cambiar F1 a Oppenheimer la extiende a 17:24 y choca con F4',
    $$UPDATE funcion SET codigo_pelicula = 4 WHERE id_funcion = 1$$,
    '23P01', 'proyeccion_sin_solapamiento');

-- Publicidad de 60 minutos para alargar el espacio 1 (usado por F1 y F4)
INSERT INTO publicidad (duracion_seg, clasificacion, publicidad) VALUES (3600, 'ATP', 'publicidad_negocio');

SELECT pg_temp.assert_rechaza(
    'N-06 Alargar el espacio publicitario de F1 en 60 min la hace chocar con F4',
    $$INSERT INTO compone (cod_espacio_publicitario, cod_publicidad)
      VALUES (1, (SELECT id_publicidad FROM publicidad WHERE duracion_seg = 3600))$$,
    '23P01', 'proyeccion_sin_solapamiento');

-- ============================================================================
-- R-02 PREVENCIÓN DE OVERBOOKING → 23505 / 23514 / 23503
-- ============================================================================

SELECT pg_temp.assert_rechaza(
    'N-07 Vender dos veces el asiento 1 de F1 en Sala 1',
    $$INSERT INTO entrada (nro_sala, id_funcion, nro_asiento, tipo_entrada, precio)
      VALUES (1, 1, 1, 'kiosko', 5000.00)$$,
    '23505', 'entrada_asiento_unico');

SELECT pg_temp.assert_rechaza(
    'N-08 Asiento 91 en Sala 4 (capacidad 90)',
    $$INSERT INTO entrada (nro_sala, id_funcion, nro_asiento, tipo_entrada, precio)
      VALUES (4, 4, 91, 'online', 5500.00)$$,
    '23514', 'excede la capacidad');

SELECT pg_temp.assert_rechaza(
    'N-09 Asiento 0 (CHECK nro_asiento > 0)',
    $$INSERT INTO entrada (nro_sala, id_funcion, nro_asiento, tipo_entrada, precio)
      VALUES (1, 1, 0, 'online', 5500.00)$$,
    '23514', 'entrada_nro_asiento_check');

SELECT pg_temp.assert_rechaza(
    'N-10 Entrada para una proyección inexistente (F1 no se proyecta en Sala 2)',
    $$INSERT INTO entrada (nro_sala, id_funcion, nro_asiento, tipo_entrada, precio)
      VALUES (2, 1, 5, 'online', 5500.00)$$,
    '23503', 'entrada_proyeccion_fk');

SELECT pg_temp.assert_rechaza(
    'N-11 Precio de entrada negativo',
    $$INSERT INTO entrada (nro_sala, id_funcion, nro_asiento, tipo_entrada, precio)
      VALUES (1, 1, 30, 'online', -1)$$,
    '23514', 'entrada_precio_check');

-- ============================================================================
-- R-04 COMPATIBILIDAD TECNOLÓGICA DE SALA → 23514
-- ============================================================================

SELECT pg_temp.assert_rechaza(
    'N-12 Función 3D (F2 Dune) en sala 2D (Sala 1)',
    $$INSERT INTO proyeccion (nro_sala, id_funcion) VALUES (1, 2)$$,
    '23514', 'requiere tecnología 3D');

SELECT pg_temp.assert_rechaza(
    'N-13 Función IMAX (F3 Inception) en sala 3D (Sala 2)',
    $$INSERT INTO proyeccion (nro_sala, id_funcion) VALUES (2, 3)$$,
    '23514', 'requiere tecnología IMAX');

SELECT pg_temp.assert_rechaza(
    'N-14 Reasignar por UPDATE la proyección 3D de F2 a la Sala 4 (2D)',
    $$UPDATE proyeccion SET nro_sala = 4 WHERE (nro_sala, id_funcion) = (2, 2)$$,
    '23514', 'requiere tecnología 3D');

-- ============================================================================
-- R-05 COMPATIBILIDAD DE CLASIFICACIÓN PUBLICIDAD vs PELÍCULA → 23514
-- ============================================================================

SELECT pg_temp.assert_rechaza(
    'N-15 Nueva función ATP (Toy Story) con espacio publicitario P-16',
    $$INSERT INTO funcion (codigo_pelicula, codigo_cartelera, cod_espacio_publicitario,
                           tipo_pelicula, idioma, fecha_hora_inicio)
      VALUES (1, 1, 3, '2D', 'TEST-N15', '2026-10-16 10:00-03')$$,
    '23514', 'Incompatibilidad etaria');

SELECT pg_temp.assert_rechaza(
    'N-16 Reasignar a F1 (ATP) el espacio publicitario P-16',
    $$UPDATE funcion SET cod_espacio_publicitario = 3 WHERE id_funcion = 1$$,
    '23514', 'Incompatibilidad etaria');

SELECT pg_temp.assert_rechaza(
    'N-17 Agregar un trailer P-18 al espacio que usan funciones ATP',
    $$INSERT INTO compone (cod_espacio_publicitario, cod_publicidad) VALUES (1, 4)$$,
    '23514', 'Incompatibilidad etaria');

SELECT pg_temp.assert_rechaza(
    'N-18 Cambiar a Toy Story (ATP) una función con espacio P-16 (F5)',
    $$UPDATE funcion SET codigo_pelicula = 1 WHERE id_funcion = 5$$,
    '23514', 'Incompatibilidad etaria');

-- ============================================================================
-- R-07 CORRESPONDENCIA DE SUCURSAL → 23503
-- ============================================================================

SELECT pg_temp.assert_rechaza(
    'N-19 Proyectar F1 (cartelera Abasto) en la Sala 5 (Rosario)',
    $$INSERT INTO proyeccion (nro_sala, id_funcion) VALUES (5, 1)$$,
    '23503', 'correspondencia de sucursal');

-- ============================================================================
-- R-08 UN GERENTE Y UN KIOSKO POR SUCURSAL → 23505
-- ============================================================================

SELECT pg_temp.assert_rechaza(
    'N-20 Segundo gerente en la sucursal Abasto',
    $$INSERT INTO empleado (dni, id_sucursal, empleado, nombre, apellido, telefono, mail, calle, numero)
      VALUES (43000111, 1, 'gerente', 'Ana', 'Duplicada', '011-5555-9999',
              'ana.duplicada@sunstar.com', 'Rivadavia', 100)$$,
    '23505', 'empleado_gerente_por_sucursal_uidx');

SELECT pg_temp.assert_rechaza(
    'N-21 Segundo kiosko en la sucursal Abasto',
    $$INSERT INTO kiosko (id_sucursal) VALUES (1)$$,
    '23505', 'kiosko_id_sucursal_key');

-- ============================================================================
-- CARTELERA: VIGENCIA Y PUBLICACIÓN
-- ============================================================================

SELECT pg_temp.assert_rechaza(
    'N-22 Cartelera solapada con la vigente de la misma sucursal',
    $$INSERT INTO cartelera (id_sucursal, fecha_inicio, fecha_fin) VALUES (1, '2026-10-20', '2026-10-27')$$,
    '23P01', 'cartelera_sucursal_periodo_excl');

SELECT pg_temp.assert_rechaza(
    'N-23 Cartelera con fecha de fin anterior a la de inicio',
    $$INSERT INTO cartelera (id_sucursal, fecha_inicio, fecha_fin) VALUES (1, '2027-01-10', '2027-01-01')$$,
    '23514', 'cartelera_fechas_orden_ck');

SELECT pg_temp.assert_rechaza(
    'N-24 Publicar una cartelera sin funciones (Rosario)',
    $$SELECT fn_validar_cartelera_publicable(2)$$,
    '23514', 'no tiene funciones');

-- Las funciones auxiliares TEST-N01/N02/N03b quedaron sin sala en la cartelera de Abasto
SELECT pg_temp.assert_rechaza(
    'N-25 Publicar una cartelera con funciones sin sala asignada (Abasto)',
    $$SELECT fn_validar_cartelera_publicable(1)$$,
    '23514', 'sin sala física asignada');

-- ============================================================================
-- DOMINIOS E INTEGRIDAD REFERENCIAL
-- ============================================================================

SELECT pg_temp.assert_rechaza(
    'N-26 Email con formato inválido (dominio email)',
    $$INSERT INTO cliente (dni, mail) VALUES (40111222, 'no-es-un-mail')$$,
    '23514', 'email');

SELECT pg_temp.assert_rechaza(
    'N-27 Código de artículo fuera del rango EAN-13 (dominio ean13)',
    $$INSERT INTO articulo (codigo, nombre, precio) VALUES (77912345678901, 'Código de 14 dígitos', 1000)$$,
    '23514', 'ean13');

SELECT pg_temp.assert_rechaza(
    'N-28 Eliminar una sala con proyecciones programadas',
    $$DELETE FROM sala WHERE nro_sala = 1$$,
    '23503', 'proyeccion');

SELECT pg_temp.assert_rechaza(
    'N-29 Eliminar una película con funciones programadas',
    $$DELETE FROM pelicula WHERE codigo_pelicula = 1$$,
    '23503', 'funcion');

-- ----------------------------------------------------------------------------
-- Resultados
-- ----------------------------------------------------------------------------
\o
:listar_resultados
SELECT pg_temp.resumen('02-casos-negativos') AS resumen;

ROLLBACK;
