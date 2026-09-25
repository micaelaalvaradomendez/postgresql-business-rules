-- ============================================================================
-- PROYECTO: Automatización e Integridad Transaccional en PostgreSQL
-- CASO: Cadena de Cines Sunstar — Motor Relacional y Reglas de Negocio
-- ARCHIVO: tests/01-casos-positivos.sql
-- DESCRIPCIÓN: Flujos válidos que el motor debe aceptar y los atributos que
--              debe derivar automáticamente (horarios, rangos, publicidad).
--
-- PRECONDICIÓN: base recién cargada con sql/01..04 (seed intacto).
-- EFECTOS: ninguno. Toda la suite corre en una transacción que se revierte;
--          cada prueba que modifica datos se aísla con un SAVEPOINT.
--
-- Referencia del seed (sucursal Abasto, 15/10/2026, hora -03):
--   Sala 1 (2D, 120)  : F1 Toy Story 14:00–16:04 | F4 Toy Story 17:00–19:04 | F5 Oppenheimer 20:00–23:25
--   Sala 2 (3D, 150)  : F2 Dune 3D 16:30–19:40
--   Sala 3 (IMAX, 200): F3 Inception IMAX 14:00–16:52
--   Sala 4 (2D, 90)   : F4 Toy Story 17:00–19:04 (multi-sala con Sala 1)
-- ============================================================================

\ir 00-helpers.sql

BEGIN;

-- ----------------------------------------------------------------------------
-- P-01 Zona horaria operativa
-- ----------------------------------------------------------------------------
SELECT pg_temp.assert_igual(
    'P-01 Zona horaria de la base: America/Argentina/Buenos_Aires',
    current_setting('TimeZone'), 'America/Argentina/Buenos_Aires');

SELECT pg_temp.assert_igual(
    'P-01 Literal sin offset se interpreta como hora local (-03)',
    '2026-10-15 14:00'::timestamptz, '2026-10-15 17:00+00'::timestamptz);

-- ----------------------------------------------------------------------------
-- P-02 Cálculo automático del horario de fin (R-03)
-- Toy Story 100 min + espacio 1 (225 s → 4 min) + 20 min de limpieza = 124 min
-- ----------------------------------------------------------------------------
SELECT pg_temp.assert_igual(
    'P-02 Duración total derivada: película + publicidad + limpieza',
    (SELECT duracion_total_min FROM funcion WHERE id_funcion = 1), 124);

SELECT pg_temp.assert_igual(
    'P-02 fecha_hora_fin derivada = inicio + duración total',
    (SELECT fecha_hora_fin FROM funcion WHERE id_funcion = 1), '2026-10-15 16:04-03'::timestamptz);

-- ----------------------------------------------------------------------------
-- P-03 Espacios publicitarios calculados desde sus piezas (R-09, R-10)
-- ----------------------------------------------------------------------------
SELECT pg_temp.assert_igual(
    'P-03 Espacio 1: duración = suma de piezas (120+45+60 s)',
    (SELECT duracion_seg FROM espacio_publicitario WHERE cod_espacio_publicitario = 1), 225);

SELECT pg_temp.assert_igual(
    'P-03 Espacio 3: clasificación = la más restrictiva de sus piezas',
    (SELECT clasificacion::text FROM espacio_publicitario WHERE cod_espacio_publicitario = 3), 'P-16');

-- ----------------------------------------------------------------------------
-- P-04 Funciones simultáneas en salas físicas distintas
-- ----------------------------------------------------------------------------
SELECT pg_temp.assert_true(
    'P-04 F1 (Sala 1) y F3 (Sala 3) se solapan en el tiempo sin conflicto',
    (SELECT a.rango_ocupacion && b.rango_ocupacion
     FROM proyeccion a, proyeccion b
     WHERE (a.nro_sala, a.id_funcion) = (1, 1)
       AND (b.nro_sala, b.id_funcion) = (3, 3)));

-- ----------------------------------------------------------------------------
-- P-05 Multi-sala: una función en dos salas y mismo asiento en cada una
-- ----------------------------------------------------------------------------
SELECT pg_temp.assert_igual(
    'P-05 F4 se proyecta en 2 salas en paralelo',
    (SELECT count(*) FROM proyeccion WHERE id_funcion = 4), 2::bigint);

SELECT pg_temp.assert_igual(
    'P-05 Asiento 1 de F4 vendido en Sala 1 y en Sala 4',
    (SELECT count(DISTINCT nro_sala) FROM entrada WHERE id_funcion = 4 AND nro_asiento = 1), 2::bigint);

SELECT pg_temp.assert_igual(
    'P-05 Mismo asiento en la misma sala para funciones distintas (F1 y F4)',
    (SELECT count(*) FROM entrada WHERE nro_sala = 1 AND nro_asiento = 1), 2::bigint);

-- ----------------------------------------------------------------------------
-- P-06 Funciones consecutivas en la misma sala sin solapamiento
-- ----------------------------------------------------------------------------
SELECT pg_temp.assert_igual(
    'P-06 Sala 1 aloja 3 funciones consecutivas',
    (SELECT count(*) FROM proyeccion WHERE nro_sala = 1), 3::bigint);

SELECT pg_temp.assert_igual(
    'P-06 Ningún par de proyecciones de una misma sala se solapa',
    (SELECT count(*) FROM proyeccion a JOIN proyeccion b
       ON a.nro_sala = b.nro_sala AND a.id_funcion < b.id_funcion
      AND a.rango_ocupacion && b.rango_ocupacion), 0::bigint);

-- ----------------------------------------------------------------------------
-- Las pruebas P-07 a P-14 modifican datos dentro de un SAVEPOINT. Los valores
-- observados se capturan en variables de psql (\gset), que no son
-- transaccionales, y se afirman después del ROLLBACK TO SAVEPOINT.
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- P-07 Rango semiabierto [inicio, fin): una función puede empezar
--      exactamente cuando termina la anterior
-- P-08 Compatibilidad descendente: una función 2D puede ir a una sala 3D
-- ----------------------------------------------------------------------------
SAVEPOINT p07;

INSERT INTO funcion (codigo_pelicula, codigo_cartelera, tipo_pelicula, idioma, fecha_hora_inicio)
VALUES (1, 1, '2D', 'TEST-P07', '2026-10-15 19:40-03');  -- F2 termina 19:40 en Sala 2 (3D)

SELECT pg_temp.sqlstate_de(
    $$INSERT INTO proyeccion (nro_sala, id_funcion)
      VALUES (2, (SELECT id_funcion FROM funcion WHERE idioma = 'TEST-P07'))$$) AS p07_estado
\gset

ROLLBACK TO SAVEPOINT p07;

SELECT pg_temp.assert_igual(
    'P-07 Función contigua aceptada (inicia 19:40, la anterior termina 19:40)',
    :'p07_estado', '00000');

SELECT pg_temp.assert_igual(
    'P-08 Función 2D aceptada en sala 3D (Sala 2)',
    :'p07_estado', '00000');

-- ----------------------------------------------------------------------------
-- P-09 Función que cruza la medianoche (imposible de validar con TIME)
-- ----------------------------------------------------------------------------
SAVEPOINT p09;

-- Toy Story sin publicidad: 100 + 20 = 120 min → 23:30 a 01:30 del día siguiente
INSERT INTO funcion (codigo_pelicula, codigo_cartelera, tipo_pelicula, idioma, fecha_hora_inicio)
VALUES (1, 1, '2D', 'TEST-P09', '2026-10-15 23:30-03');

INSERT INTO proyeccion (nro_sala, id_funcion)
VALUES (4, (SELECT id_funcion FROM funcion WHERE idioma = 'TEST-P09'));

SELECT upper(p.rango_ocupacion) AS p09_fin
FROM proyeccion p JOIN funcion f USING (id_funcion)
WHERE f.idioma = 'TEST-P09'
\gset

ROLLBACK TO SAVEPOINT p09;

SELECT pg_temp.assert_igual(
    'P-09 Función trasnoche termina al día siguiente (16/10 01:30)',
    :'p09_fin'::timestamptz, '2026-10-16 01:30-03'::timestamptz);

-- ----------------------------------------------------------------------------
-- P-10 Cambio de horario se propaga a la proyección física
-- ----------------------------------------------------------------------------
SAVEPOINT p10;

UPDATE funcion SET fecha_hora_inicio = '2026-10-15 13:00-03' WHERE id_funcion = 3;

SELECT rango_ocupacion AS p10_rango FROM proyeccion WHERE id_funcion = 3
\gset

ROLLBACK TO SAVEPOINT p10;

SELECT pg_temp.assert_igual(
    'P-10 Adelantar F3 a 13:00 actualiza el rango de la Sala 3',
    :'p10_rango'::tstzrange, tstzrange('2026-10-15 13:00-03', '2026-10-15 15:52-03', '[)'));

-- ----------------------------------------------------------------------------
-- P-11 Cambio de película recalcula el fin y lo propaga a la proyección
-- ----------------------------------------------------------------------------
SAVEPOINT p11;

-- F3 pasa a Dune (166 min): 166 + 4 + 20 = 190 min → 14:00 a 17:10
UPDATE funcion SET codigo_pelicula = 2 WHERE id_funcion = 3;

SELECT f.fecha_hora_fin AS p11_fin, upper(p.rango_ocupacion) AS p11_fin_sala
FROM funcion f JOIN proyeccion p USING (id_funcion)
WHERE f.id_funcion = 3
\gset

ROLLBACK TO SAVEPOINT p11;

SELECT pg_temp.assert_igual(
    'P-11 Nueva película recalcula fecha_hora_fin (17:10)',
    :'p11_fin'::timestamptz, '2026-10-15 17:10-03'::timestamptz);

SELECT pg_temp.assert_igual(
    'P-11 El rango de la Sala 3 refleja el nuevo fin',
    :'p11_fin_sala'::timestamptz, '2026-10-15 17:10-03'::timestamptz);

-- ----------------------------------------------------------------------------
-- P-12 Atributos derivados no editables manualmente
-- ----------------------------------------------------------------------------
SAVEPOINT p12;

UPDATE funcion SET fecha_hora_fin = '2026-10-15 14:05-03', duracion_total_min = 5 WHERE id_funcion = 1;

UPDATE proyeccion
SET rango_ocupacion = tstzrange('2026-10-15 10:00-03', '2026-10-15 10:01-03')
WHERE (nro_sala, id_funcion) = (1, 1);

SELECT f.fecha_hora_fin AS p12_fin, p.rango_ocupacion AS p12_rango
FROM funcion f JOIN proyeccion p USING (id_funcion)
WHERE (p.nro_sala, p.id_funcion) = (1, 1)
\gset

ROLLBACK TO SAVEPOINT p12;

SELECT pg_temp.assert_igual(
    'P-12 Editar fecha_hora_fin a mano: el motor la recalcula (16:04)',
    :'p12_fin'::timestamptz, '2026-10-15 16:04-03'::timestamptz);

SELECT pg_temp.assert_igual(
    'P-12 Editar rango_ocupacion a mano: el motor lo deriva de la función',
    :'p12_rango'::tstzrange, tstzrange('2026-10-15 14:00-03', '2026-10-15 16:04-03', '[)'));

-- ----------------------------------------------------------------------------
-- P-13 Recálculo del espacio publicitario ante INSERT / UPDATE / DELETE en compone
-- ----------------------------------------------------------------------------
SAVEPOINT p13;

INSERT INTO espacio_publicitario DEFAULT VALUES RETURNING cod_espacio_publicitario AS p13_esp_a
\gset
INSERT INTO espacio_publicitario DEFAULT VALUES RETURNING cod_espacio_publicitario AS p13_esp_b
\gset

-- Trailer ATP (120 s) + Trailer P-18 (160 s)
INSERT INTO compone (cod_espacio_publicitario, cod_publicidad) VALUES (:p13_esp_a, 1), (:p13_esp_a, 4);

SELECT duracion_seg AS p13_ins_dur, clasificacion AS p13_ins_clasif
FROM espacio_publicitario WHERE cod_espacio_publicitario = :p13_esp_a
\gset

DELETE FROM compone WHERE (cod_espacio_publicitario, cod_publicidad) = (:p13_esp_a, 4);

SELECT duracion_seg AS p13_del_dur, clasificacion AS p13_del_clasif
FROM espacio_publicitario WHERE cod_espacio_publicitario = :p13_esp_a
\gset

UPDATE compone SET cod_espacio_publicitario = :p13_esp_b
WHERE (cod_espacio_publicitario, cod_publicidad) = (:p13_esp_a, 1);

SELECT a.duracion_seg AS p13_upd_origen, b.duracion_seg AS p13_upd_destino
FROM espacio_publicitario a, espacio_publicitario b
WHERE a.cod_espacio_publicitario = :p13_esp_a AND b.cod_espacio_publicitario = :p13_esp_b
\gset

ROLLBACK TO SAVEPOINT p13;

-- Las secuencias no son transaccionales: el código exacto depende de corridas
-- previas, por eso se afirma que supera los códigos cargados por el seed (1..3).
SELECT pg_temp.assert_true(
    'P-13 Alta de espacio nuevo tras el seed (secuencia identity sincronizada)',
    :p13_esp_a > 3, format('código asignado %s', :p13_esp_a));

SELECT pg_temp.assert_igual(
    'P-13 INSERT en compone: duración = 120 + 160 s',
    :p13_ins_dur, 280);

SELECT pg_temp.assert_igual(
    'P-13 INSERT en compone: clasificación máxima P-18',
    :'p13_ins_clasif', 'P-18');

SELECT pg_temp.assert_igual(
    'P-13 DELETE en compone: al quitar el trailer P-18 vuelve a 120 s',
    :p13_del_dur, 120);

SELECT pg_temp.assert_igual(
    'P-13 DELETE en compone: la clasificación vuelve a ATP',
    :'p13_del_clasif', 'ATP');

SELECT pg_temp.assert_igual(
    'P-13 UPDATE en compone: mover una pieza recalcula origen y destino',
    format('%s,%s', :p13_upd_origen, :p13_upd_destino), '0,120');

-- ----------------------------------------------------------------------------
-- P-14 Cambio en un espacio publicitario en uso se propaga a sus funciones
-- ----------------------------------------------------------------------------
SAVEPOINT p14;

-- Espacio 1 (usado por F1 y F4) + publicidad de 30 s: 255 s → 5 min
INSERT INTO compone (cod_espacio_publicitario, cod_publicidad) VALUES (1, 6);

SELECT string_agg(to_char(fecha_hora_fin, 'HH24:MI'), ',' ORDER BY id_funcion) AS p14_fines
FROM funcion WHERE cod_espacio_publicitario = 1
\gset

SELECT count(*) AS p14_sincronizadas
FROM proyeccion p JOIN funcion f USING (id_funcion)
WHERE f.cod_espacio_publicitario = 1
  AND p.rango_ocupacion = tstzrange(f.fecha_hora_inicio, f.fecha_hora_fin, '[)')
\gset

ROLLBACK TO SAVEPOINT p14;

SELECT pg_temp.assert_igual(
    'P-14 F1 y F4 extienden su fin en 1 minuto (16:05 y 19:05)',
    :'p14_fines', '16:05,19:05');

SELECT pg_temp.assert_igual(
    'P-14 Las 3 proyecciones afectadas (Salas 1 y 4) quedan sincronizadas',
    :p14_sincronizadas, 3);

-- ----------------------------------------------------------------------------
-- P-15 Venta en el límite exacto de capacidad de la sala
-- ----------------------------------------------------------------------------
SELECT pg_temp.assert_acepta(
    'P-15 Asiento 90 en Sala 4 (capacidad 90)',
    $$INSERT INTO entrada (nro_sala, id_funcion, nro_asiento, tipo_entrada, precio)
      VALUES (4, 4, 90, 'online', 5500.00)$$);

-- ----------------------------------------------------------------------------
-- P-16 Cartelera publicable: todas sus funciones tienen sala asignada
-- ----------------------------------------------------------------------------
SELECT pg_temp.assert_true(
    'P-16 Cartelera de Abasto cumple requisitos de publicación',
    fn_validar_cartelera_publicable(1));

-- ----------------------------------------------------------------------------
-- P-17 Vistas operativas (sql/05-views.sql)
-- ----------------------------------------------------------------------------
SELECT pg_temp.assert_igual(
    'P-17 v_programacion: una fila por proyección física',
    (SELECT count(*) FROM v_programacion), (SELECT count(*) FROM proyeccion));

SELECT pg_temp.assert_igual(
    'P-17 v_programacion: ocupación de F1 en Sala 1 (3 de 120 = 2.5 %)',
    (SELECT ocupacion_pct FROM v_programacion WHERE (nro_sala, id_funcion) = (1, 1)), 2.5);

SELECT pg_temp.assert_igual(
    'P-17 v_programacion: sucursales que exhiben Toy Story 5',
    (SELECT string_agg(DISTINCT sucursal, ',') FROM v_programacion WHERE pelicula = 'Toy Story 5'),
    'Sunstar Shopping Abasto');

SELECT pg_temp.assert_igual(
    'P-17 v_publicidad_por_funcion: F1 proyecta las 3 piezas del espacio 1',
    (SELECT count(*) FROM v_publicidad_por_funcion WHERE id_funcion = 1), 3::bigint);

SELECT pg_temp.assert_igual(
    'P-17 v_gerente_por_sucursal: las 3 sucursales tienen gerente',
    (SELECT count(legajo) FROM v_gerente_por_sucursal), 3::bigint);

SELECT pg_temp.assert_igual(
    'P-17 v_limpieza_por_sala: 4 asignaciones de limpieza',
    (SELECT count(*) FROM v_limpieza_por_sala), 4::bigint);

-- ----------------------------------------------------------------------------
-- Resultados
-- ----------------------------------------------------------------------------
\o
:listar_resultados
SELECT pg_temp.resumen('01-casos-positivos') AS resumen;

ROLLBACK;
