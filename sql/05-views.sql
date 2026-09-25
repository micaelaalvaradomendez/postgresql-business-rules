-- ============================================================================
-- PROYECTO: Automatización e Integridad Transaccional en PostgreSQL
-- CASO: Cadena de Cines Sunstar — Motor Relacional y Reglas de Negocio
-- ARCHIVO: sql/05-views.sql
-- DESCRIPCIÓN: Vistas operativas de consulta. Reemplazan las consultas ad hoc
--              del modelo original. Se definen con security_invoker para que
--              apliquen los permisos de quien consulta, no los del creador.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. PROGRAMACIÓN: una fila por proyección física, con ocupación de la sala
-- ----------------------------------------------------------------------------
-- Ejemplo: sucursales donde se exhibe una película
--   SELECT DISTINCT sucursal FROM v_programacion WHERE pelicula = 'Toy Story 5';
CREATE OR REPLACE VIEW v_programacion
WITH (security_invoker = true) AS
SELECT
    su.nombre                                         AS sucursal,
    p.nro_sala,
    sa.sala                                           AS tipo_sala,
    f.id_funcion,
    pe.titulo                                         AS pelicula,
    pe.clasificacion,
    f.tipo_pelicula                                   AS formato,
    f.idioma,
    f.fecha_hora_inicio                               AS inicio,
    f.fecha_hora_fin                                  AS fin,
    sa.cant_asientos                                  AS capacidad,
    count(e.codigo)                                   AS entradas_vendidas,
    round(100.0 * count(e.codigo) / sa.cant_asientos, 1) AS ocupacion_pct
FROM proyeccion p
JOIN funcion   f  ON f.id_funcion = p.id_funcion
JOIN pelicula  pe ON pe.codigo_pelicula = f.codigo_pelicula
JOIN sala      sa ON sa.nro_sala = p.nro_sala
JOIN sucursal  su ON su.id_sucursal = sa.id_sucursal
LEFT JOIN entrada e ON (e.nro_sala, e.id_funcion) = (p.nro_sala, p.id_funcion)
GROUP BY su.nombre, p.nro_sala, sa.sala, f.id_funcion, pe.titulo, pe.clasificacion,
         f.tipo_pelicula, f.idioma, f.fecha_hora_inicio, f.fecha_hora_fin, sa.cant_asientos;

COMMENT ON VIEW v_programacion IS
'Programación por proyección física con entradas vendidas y porcentaje de ocupación de la sala';

-- ----------------------------------------------------------------------------
-- 2. PUBLICIDAD POR FUNCIÓN: piezas que se proyectan antes de cada función
-- ----------------------------------------------------------------------------
-- Ejemplo: SELECT * FROM v_publicidad_por_funcion WHERE pelicula = 'Toy Story 5';
CREATE OR REPLACE VIEW v_publicidad_por_funcion
WITH (security_invoker = true) AS
SELECT
    f.id_funcion,
    pe.titulo                  AS pelicula,
    pe.clasificacion           AS clasificacion_pelicula,
    f.cod_espacio_publicitario,
    pu.id_publicidad,
    pu.publicidad              AS tipo_publicidad,
    pu.clasificacion           AS clasificacion_publicidad,
    pu.duracion_seg
FROM funcion f
JOIN pelicula   pe ON pe.codigo_pelicula = f.codigo_pelicula
JOIN compone    c  ON c.cod_espacio_publicitario = f.cod_espacio_publicitario
JOIN publicidad pu ON pu.id_publicidad = c.cod_publicidad;

COMMENT ON VIEW v_publicidad_por_funcion IS
'Piezas publicitarias que componen el bloque previo de cada función';

-- ----------------------------------------------------------------------------
-- 3. GERENTE POR SUCURSAL: incluye sucursales sin gerente asignado (NULL)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_gerente_por_sucursal
WITH (security_invoker = true) AS
SELECT
    su.nombre                        AS sucursal,
    e.legajo,
    e.nombre || ' ' || e.apellido    AS gerente,
    e.mail
FROM sucursal su
LEFT JOIN empleado e ON e.id_sucursal = su.id_sucursal AND e.empleado = 'gerente';

COMMENT ON VIEW v_gerente_por_sucursal IS
'Gerente de cada sucursal; las sucursales sin gerente aparecen con legajo NULL';

-- ----------------------------------------------------------------------------
-- 4. LIMPIEZA POR SALA: personal de limpieza asignado a cada sala
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_limpieza_por_sala
WITH (security_invoker = true) AS
SELECT
    su.nombre                        AS sucursal,
    sa.nro_sala,
    sa.sala                          AS tipo_sala,
    e.legajo,
    e.nombre || ' ' || e.apellido    AS empleado
FROM limpia_la l
JOIN empleado e  ON e.legajo = l.id_empleado
JOIN sala     sa ON sa.nro_sala = l.nro_sala
JOIN sucursal su ON su.id_sucursal = sa.id_sucursal
WHERE e.empleado = 'limpieza';

COMMENT ON VIEW v_limpieza_por_sala IS
'Asignación del personal de limpieza a las salas físicas de cada sucursal';
