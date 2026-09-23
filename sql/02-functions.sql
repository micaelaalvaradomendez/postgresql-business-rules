-- ============================================================================
-- PROYECTO: Automatización e Integridad Transaccional en PostgreSQL
-- CASO: Cadena de Cines Sunstar — Motor Relacional y Reglas de Negocio
-- ARCHIVO: sql/02-functions.sql
-- DESCRIPCIÓN: Funciones PL/pgSQL reutilizables con SECURITY INVOKER,
--              captura estructurada de excepciones y lógica de dominio.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. FUNCIÓN AUXILIAR: Jerarquía y Comparación de Clasificaciones Etarias
-- ----------------------------------------------------------------------------
-- Provee una escala numérica inmutable para comparar clasificaciones sin
-- depender del orden léxico de los identificadores ENUM:
-- ATP (1) < P-13 (2) < P-16 (3) < P-18 (4) < P-21 (5)
CREATE OR REPLACE FUNCTION fn_peso_clasificacion(p_clasificacion clasificacion_pelicula)
RETURNS integer
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT CASE p_clasificacion
        WHEN 'ATP'  THEN 1
        WHEN 'P-13' THEN 2
        WHEN 'P-16' THEN 3
        WHEN 'P-18' THEN 4
        WHEN 'P-21' THEN 5
        ELSE 0
    END;
$$;

COMMENT ON FUNCTION fn_peso_clasificacion(clasificacion_pelicula) IS
'Retorna el peso ordinal entero de una clasificación etaria para comparaciones de compatibilidad';

-- ----------------------------------------------------------------------------
-- 2. FUNCIÓN: Cálculo Automático de Duración Total y Horario de Fin
-- ----------------------------------------------------------------------------
-- Regla de Negocio R-03: La duración final de una función se deriva de:
-- duracion_pelicula + duracion_publicidad + 20 min de limpieza/reacondicionamiento.
CREATE OR REPLACE FUNCTION fn_calcular_fin_funcion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_duracion_pelicula_min integer;
    v_duracion_publicidad_seg integer := 0;
    v_duracion_publicidad_min integer := 0;
    v_limpieza_min CONSTANT integer := 20; -- Tiempo técnico de sanitización de sala
BEGIN
    -- 1. Obtener la duración en minutos de la película programada
    SELECT duracion_min INTO STRICT v_duracion_pelicula_min
    FROM pelicula
    WHERE codigo_pelicula = NEW.codigo_pelicula;

    -- 2. Obtener duración del bloque publicitario (si existe asignado)
    IF NEW.cod_espacio_publicitario IS NOT NULL THEN
        SELECT COALESCE(duracion_seg, 0) INTO v_duracion_publicidad_seg
        FROM espacio_publicitario
        WHERE cod_espacio_publicitario = NEW.cod_espacio_publicitario;

        -- Convertir segundos a minutos (redondeo hacia arriba)
        v_duracion_publicidad_min := CEIL(v_duracion_publicidad_seg::numeric / 60.0)::integer;
    END IF;

    -- 3. Calcular duración consolidada y marca temporal final
    NEW.duracion_total_min := v_duracion_pelicula_min + v_duracion_publicidad_min + v_limpieza_min;
    NEW.fecha_hora_fin := NEW.fecha_hora_inicio + make_interval(mins => NEW.duracion_total_min);

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION fn_calcular_fin_funcion() IS
'Trigger function: calcula la duración total e instante fecha_hora_fin antes de guardar en funcion';

-- ----------------------------------------------------------------------------
-- 3. FUNCIÓN: Sincronización Automática del Rango de Proyección Física
-- ----------------------------------------------------------------------------
-- Si al asignar una proyección física a sala no se especifica el rango_ocupacion,
-- se deriva de forma atómica a partir de [fecha_hora_inicio, fecha_hora_fin) de la función.
CREATE OR REPLACE FUNCTION fn_sincronizar_rango_proyeccion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_inicio timestamptz;
    v_fin    timestamptz;
BEGIN
    IF NEW.rango_ocupacion IS NULL THEN
        SELECT fecha_hora_inicio, fecha_hora_fin
        INTO STRICT v_inicio, v_fin
        FROM funcion
        WHERE id_funcion = NEW.id_funcion;

        NEW.rango_ocupacion := tstzrange(v_inicio, v_fin, '[)');
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION fn_sincronizar_rango_proyeccion() IS
'Trigger function: auto-puebla el rango de ocupación [inicio, fin) en proyeccion a partir de funcion';

-- ----------------------------------------------------------------------------
-- 4. FUNCIÓN: Propagación de Modificación de Horario a Proyecciones Físicas
-- ----------------------------------------------------------------------------
-- Si se modifica la hora de inicio o la película de una función, se actualiza
-- el rango_ocupacion de todas las salas físicas donde se proyecta. Si la nueva
-- ventana temporal colisiona con otra proyección, la restricción GiST aborta el UPDATE.
CREATE OR REPLACE FUNCTION fn_actualizar_rango_proyecciones_de_funcion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    UPDATE proyeccion
    SET rango_ocupacion = tstzrange(NEW.fecha_hora_inicio, NEW.fecha_hora_fin, '[)')
    WHERE id_funcion = NEW.id_funcion;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION fn_actualizar_rango_proyecciones_de_funcion() IS
'Trigger function: propaga cambios de horario de funcion hacia proyeccion, disparando validación GiST';

-- ----------------------------------------------------------------------------
-- 5. FUNCIÓN: Validación de Compatibilidad Tecnológica de Sala (2D, 3D, IMAX)
-- ----------------------------------------------------------------------------
-- Regla de Negocio R-04: Una función en 3D solo puede proyectarse en salas 3D o IMAX.
-- Una función IMAX solo puede proyectarse en sala IMAX. 2D es soportado por cualquier sala.
CREATE OR REPLACE FUNCTION fn_validar_compatibilidad_sala()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_tipo_funcion tipo_sala;
    v_tipo_sala    tipo_sala;
BEGIN
    -- Obtener el formato de la función
    SELECT tipo_pelicula INTO STRICT v_tipo_funcion
    FROM funcion
    WHERE id_funcion = NEW.id_funcion;

    -- Obtener la tecnología física de la sala
    SELECT sala INTO STRICT v_tipo_sala
    FROM sala
    WHERE nro_sala = NEW.nro_sala;

    -- Validar compatibilidad
    IF v_tipo_funcion = '3D' AND v_tipo_sala NOT IN ('3D', 'IMAX') THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514', -- check_violation
            MESSAGE = format('Incompatibilidad de sala: La función %s requiere tecnología 3D, pero la sala %s es %s',
                             NEW.id_funcion, NEW.nro_sala, v_tipo_sala),
            HINT = 'Asigne la función 3D a una sala con tecnología 3D o IMAX';
    END IF;

    IF v_tipo_funcion = 'IMAX' AND v_tipo_sala <> 'IMAX' THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514', -- check_violation
            MESSAGE = format('Incompatibilidad de sala: La función %s requiere tecnología IMAX, pero la sala %s es %s',
                             NEW.id_funcion, NEW.nro_sala, v_tipo_sala),
            HINT = 'Asigne la función IMAX exclusivamente a una sala equipada con IMAX';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION fn_validar_compatibilidad_sala() IS
'Trigger function: rechaza asignaciones de proyecciones 3D o IMAX a salas sin el equipamiento requerido';

-- ----------------------------------------------------------------------------
-- 6. FUNCIÓN: Validación de Correspondencia de Sucursal
-- ----------------------------------------------------------------------------
-- Regla de Negocio R-07: Una función programada en la cartelera de una sucursal
-- solo puede proyectarse en salas físicas de esa misma sucursal.
CREATE OR REPLACE FUNCTION fn_validar_sucursal_proyeccion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_sucursal_sala      integer;
    v_sucursal_cartelera integer;
BEGIN
    SELECT id_sucursal INTO STRICT v_sucursal_sala
    FROM sala
    WHERE nro_sala = NEW.nro_sala;

    SELECT c.id_sucursal INTO STRICT v_sucursal_cartelera
    FROM funcion f
    JOIN cartelera c ON f.codigo_cartelera = c.codigo_cartelera
    WHERE f.id_funcion = NEW.id_funcion;

    IF v_sucursal_sala <> v_sucursal_cartelera THEN
        RAISE EXCEPTION USING
            ERRCODE = '23503', -- foreign_key_violation
            MESSAGE = format('Violación de correspondencia de sucursal: La sala física %s pertenece a la sucursal %s, pero la función %s corresponde a la cartelera de la sucursal %s',
                             NEW.nro_sala, v_sucursal_sala, NEW.id_funcion, v_sucursal_cartelera),
            HINT = 'Una proyección física solo puede asociarse a salas de la misma sucursal de la cartelera';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION fn_validar_sucursal_proyeccion() IS
'Trigger function: garantiza que la sala física y la cartelera de la función pertenezcan a la misma sucursal';

-- ----------------------------------------------------------------------------
-- 7. FUNCIÓN: Validación de Límite de Asientos (Capacidad Física de Sala)
-- ----------------------------------------------------------------------------
-- Regla de Negocio R-06: El número de asiento vendido en una entrada debe
-- encontrarse dentro del aforo disponible de la sala física asignada.
CREATE OR REPLACE FUNCTION fn_validar_numero_asiento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_capacidad_sala integer;
BEGIN
    -- Obtener la capacidad real de la sala física correspondiente
    SELECT cant_asientos INTO STRICT v_capacidad_sala
    FROM sala
    WHERE nro_sala = NEW.nro_sala;

    IF NEW.nro_asiento > v_capacidad_sala THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514', -- check_violation
            MESSAGE = format('Asiento inválido: El asiento solicitado %s excede la capacidad total de la sala %s (capacidad máxima: %s butacas)',
                             NEW.nro_asiento, NEW.nro_sala, v_capacidad_sala),
            HINT = format('Seleccione un asiento entre 1 y %s', v_capacidad_sala);
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION fn_validar_numero_asiento() IS
'Trigger function: previene la emisión de tickets para números de asiento superiores a la capacidad de la sala';

-- ----------------------------------------------------------------------------
-- 8. FUNCIÓN: Recálculo Reactivo de Espacio Publicitario (INSERT / UPDATE / DELETE)
-- ----------------------------------------------------------------------------
-- Reglas de Negocio R-09 y R-10:
-- - La duración del espacio es la suma de sus piezas publicitarias.
-- - La clasificación etaria del espacio es la más restrictiva de sus publicidades.
-- Este trigger se dispara ante altas, modificaciones o bajas en la tabla compone.
CREATE OR REPLACE FUNCTION fn_recalcular_espacio_publicitario()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_cod_espacio integer;
    v_duracion_total integer;
    v_clasif_max clasificacion_pelicula;
BEGIN
    -- Determinar el espacio publicitario afectado según la operación DML
    IF TG_OP = 'DELETE' THEN
        v_cod_espacio := OLD.cod_espacio_publicitario;
    ELSE
        v_cod_espacio := NEW.cod_espacio_publicitario;
    END IF;

    -- Calcular duración acumulada en segundos
    SELECT COALESCE(SUM(p.duracion_seg), 0)
    INTO v_duracion_total
    FROM compone c
    JOIN publicidad p ON c.cod_publicidad = p.id_publicidad
    WHERE c.cod_espacio_publicitario = v_cod_espacio;

    -- Calcular la clasificación más restrictiva
    SELECT CASE
        WHEN bool_or(p.clasificacion = 'P-21') THEN 'P-21'::clasificacion_pelicula
        WHEN bool_or(p.clasificacion = 'P-18') THEN 'P-18'::clasificacion_pelicula
        WHEN bool_or(p.clasificacion = 'P-16') THEN 'P-16'::clasificacion_pelicula
        WHEN bool_or(p.clasificacion = 'P-13') THEN 'P-13'::clasificacion_pelicula
        ELSE 'ATP'::clasificacion_pelicula
    END
    INTO v_clasif_max
    FROM compone c
    JOIN publicidad p ON c.cod_publicidad = p.id_publicidad
    WHERE c.cod_espacio_publicitario = v_cod_espacio;

    -- Actualizar el bloque publicitario
    UPDATE espacio_publicitario
    SET duracion_seg = v_duracion_total,
        clasificacion = COALESCE(v_clasif_max, 'ATP'::clasificacion_pelicula)
    WHERE cod_espacio_publicitario = v_cod_espacio;

    -- En caso de UPDATE que cambie de cod_espacio_publicitario, recalcular también el anterior
    IF TG_OP = 'UPDATE' AND OLD.cod_espacio_publicitario <> NEW.cod_espacio_publicitario THEN
        SELECT COALESCE(SUM(p.duracion_seg), 0)
        INTO v_duracion_total
        FROM compone c
        JOIN publicidad p ON c.cod_publicidad = p.id_publicidad
        WHERE c.cod_espacio_publicitario = OLD.cod_espacio_publicitario;

        SELECT CASE
            WHEN bool_or(p.clasificacion = 'P-21') THEN 'P-21'::clasificacion_pelicula
            WHEN bool_or(p.clasificacion = 'P-18') THEN 'P-18'::clasificacion_pelicula
            WHEN bool_or(p.clasificacion = 'P-16') THEN 'P-16'::clasificacion_pelicula
            WHEN bool_or(p.clasificacion = 'P-13') THEN 'P-13'::clasificacion_pelicula
            ELSE 'ATP'::clasificacion_pelicula
        END
        INTO v_clasif_max
        FROM compone c
        JOIN publicidad p ON c.cod_publicidad = p.id_publicidad
        WHERE c.cod_espacio_publicitario = OLD.cod_espacio_publicitario;

        UPDATE espacio_publicitario
        SET duracion_seg = v_duracion_total,
            clasificacion = COALESCE(v_clasif_max, 'ATP'::clasificacion_pelicula)
        WHERE cod_espacio_publicitario = OLD.cod_espacio_publicitario;
    END IF;

    RETURN NULL; -- Trigger de tipo AFTER
END;
$$;

COMMENT ON FUNCTION fn_recalcular_espacio_publicitario() IS
'Trigger function: recalcula reactivamente duración y clasificación máxima del espacio ante cambios en compone';

-- ----------------------------------------------------------------------------
-- 9. FUNCIÓN: Validación de Compatibilidad Etaria Película vs. Publicidad
-- ----------------------------------------------------------------------------
-- Regla de Negocio R-05: El espacio publicitario proyectado no puede tener
-- una clasificación más restrictiva que la película que se va a exhibir.
CREATE OR REPLACE FUNCTION fn_validar_clasificacion_espacio_pelicula()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_clasif_pelicula clasificacion_pelicula;
    v_clasif_espacio  clasificacion_pelicula;
BEGIN
    -- Si no tiene espacio publicitario asignado, la validación no aplica
    IF NEW.cod_espacio_publicitario IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT clasificacion INTO STRICT v_clasif_pelicula
    FROM pelicula
    WHERE codigo_pelicula = NEW.codigo_pelicula;

    SELECT clasificacion INTO STRICT v_clasif_espacio
    FROM espacio_publicitario
    WHERE cod_espacio_publicitario = NEW.cod_espacio_publicitario;

    IF fn_peso_clasificacion(v_clasif_espacio) > fn_peso_clasificacion(v_clasif_pelicula) THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514', -- check_violation
            MESSAGE = format('Incompatibilidad etaria: El espacio publicitario %s tiene clasificación %s, que es más restrictiva que la película %s (%s)',
                             NEW.cod_espacio_publicitario, v_clasif_espacio, NEW.codigo_pelicula, v_clasif_pelicula),
            HINT = 'Asigne un espacio publicitario con clasificación igual o menor a la de la película exhibida';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION fn_validar_clasificacion_espacio_pelicula() IS
'Trigger function: impide asignar publicidad clasificada para mayores en funciones de películas familiares o menores';

-- ----------------------------------------------------------------------------
-- 10. FUNCIÓN DE GOBIERNO / PROCEDIMIENTO: Validación de Cartelera Publicable
-- ----------------------------------------------------------------------------
-- Resuelve el problema del "huevo y la gallina". Permite verificar que una cartelera
-- tenga al menos una función y que cada función tenga al menos una sala antes de publicar.
CREATE OR REPLACE FUNCTION fn_validar_cartelera_publicable(p_codigo_cartelera integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_cant_funciones integer;
    v_funciones_sin_sala integer;
BEGIN
    -- 1. Verificar existencia de funciones
    SELECT COUNT(*) INTO v_cant_funciones
    FROM funcion
    WHERE codigo_cartelera = p_codigo_cartelera;

    IF v_cant_funciones = 0 THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514',
            MESSAGE = format('La cartelera %s no tiene funciones asignadas', p_codigo_cartelera),
            HINT = 'Programe al menos una función antes de publicar la cartelera';
    END IF;

    -- 2. Verificar que cada función tenga al menos una proyección en sala física
    SELECT COUNT(*) INTO v_funciones_sin_sala
    FROM funcion f
    LEFT JOIN proyeccion p ON f.id_funcion = p.id_funcion
    WHERE f.codigo_cartelera = p_codigo_cartelera
      AND p.nro_sala IS NULL;

    IF v_funciones_sin_sala > 0 THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514',
            MESSAGE = format('La cartelera %s posee %s funciones sin sala física asignada',
                             p_codigo_cartelera, v_funciones_sin_sala),
            HINT = 'Asigne una sala física en proyeccion para cada función de la cartelera';
    END IF;

    RETURN true;
END;
$$;

COMMENT ON FUNCTION fn_validar_cartelera_publicable(integer) IS
'Procedimiento de verificación: valida que una cartelera cumpla todos los requisitos de publicación operativa';

