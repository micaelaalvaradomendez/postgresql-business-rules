-- ============================================================================
-- PROYECTO: Automatización e Integridad Transaccional en PostgreSQL
-- CASO: Cadena de Cines Sunstar — Motor Relacional y Reglas de Negocio
-- ARCHIVO: sql/03-triggers.sql
-- DESCRIPCIÓN: Asociación de triggers para ejecución automática de reglas
--              de negocio en inserciones, modificaciones y eliminaciones.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. TRIGGERS SOBRE TABLA: funcion
-- ----------------------------------------------------------------------------

-- Trigger 1: Cálculo automático de fecha_hora_fin antes de persistir la función.
-- Se dispara ante cualquier UPDATE (no solo UPDATE OF ...) para que
-- duracion_total_min y fecha_hora_fin no puedan editarse manualmente.
DROP TRIGGER IF EXISTS trg_funcion_calcular_fin ON funcion;
CREATE TRIGGER trg_funcion_calcular_fin
BEFORE INSERT OR UPDATE
ON funcion
FOR EACH ROW
EXECUTE FUNCTION fn_calcular_fin_funcion();

-- Trigger 2: Validación etaria película vs espacio publicitario
DROP TRIGGER IF EXISTS trg_funcion_validar_clasificacion ON funcion;
CREATE TRIGGER trg_funcion_validar_clasificacion
BEFORE INSERT OR UPDATE OF codigo_pelicula, cod_espacio_publicitario
ON funcion
FOR EACH ROW
EXECUTE FUNCTION fn_validar_clasificacion_espacio_pelicula();

-- Trigger 3: Propagación de modificaciones horarias a las proyecciones en sala física.
-- Se usa WHEN en lugar de UPDATE OF: UPDATE OF solo considera las columnas del
-- SET y no detecta el fecha_hora_fin recalculado por el Trigger 1 (p. ej. al
-- cambiar la película o el espacio publicitario).
DROP TRIGGER IF EXISTS trg_funcion_propagar_horario ON funcion;
CREATE TRIGGER trg_funcion_propagar_horario
AFTER UPDATE
ON funcion
FOR EACH ROW
WHEN (OLD.fecha_hora_inicio IS DISTINCT FROM NEW.fecha_hora_inicio
      OR OLD.fecha_hora_fin IS DISTINCT FROM NEW.fecha_hora_fin)
EXECUTE FUNCTION fn_actualizar_rango_proyecciones_de_funcion();

-- ----------------------------------------------------------------------------
-- 2. TRIGGERS SOBRE TABLA: proyeccion
-- ----------------------------------------------------------------------------

-- Trigger 4: Derivación de rango_ocupacion desde la función (no editable manualmente)
DROP TRIGGER IF EXISTS trg_proyeccion_sincronizar_rango ON proyeccion;
CREATE TRIGGER trg_proyeccion_sincronizar_rango
BEFORE INSERT OR UPDATE
ON proyeccion
FOR EACH ROW
EXECUTE FUNCTION fn_sincronizar_rango_proyeccion();

-- Trigger 5: Validación de compatibilidad tecnológica de formato (2D, 3D, IMAX)
DROP TRIGGER IF EXISTS trg_proyeccion_validar_compatibilidad ON proyeccion;
CREATE TRIGGER trg_proyeccion_validar_compatibilidad
BEFORE INSERT OR UPDATE OF nro_sala, id_funcion
ON proyeccion
FOR EACH ROW
EXECUTE FUNCTION fn_validar_compatibilidad_sala();

-- Trigger 6: Validación de correspondencia entre sucursal de sala y de cartelera
DROP TRIGGER IF EXISTS trg_proyeccion_validar_sucursal ON proyeccion;
CREATE TRIGGER trg_proyeccion_validar_sucursal
BEFORE INSERT OR UPDATE OF nro_sala, id_funcion
ON proyeccion
FOR EACH ROW
EXECUTE FUNCTION fn_validar_sucursal_proyeccion();

-- ----------------------------------------------------------------------------
-- 3. TRIGGERS SOBRE TABLA: entrada
-- ----------------------------------------------------------------------------

-- Trigger 7: Validación de que el asiento emitido no exceda el aforo de la sala física
DROP TRIGGER IF EXISTS trg_entrada_validar_asiento ON entrada;
CREATE TRIGGER trg_entrada_validar_asiento
BEFORE INSERT OR UPDATE OF nro_sala, id_funcion, nro_asiento
ON entrada
FOR EACH ROW
EXECUTE FUNCTION fn_validar_numero_asiento();

-- ----------------------------------------------------------------------------
-- 4. TRIGGERS SOBRE TABLA: compone
-- ----------------------------------------------------------------------------

-- Trigger 8: Recálculo reactivo de duración y clasificación máxima del bloque publicitario
DROP TRIGGER IF EXISTS trg_compone_recalcular_espacio ON compone;
CREATE TRIGGER trg_compone_recalcular_espacio
AFTER INSERT OR UPDATE OR DELETE
ON compone
FOR EACH ROW
EXECUTE FUNCTION fn_recalcular_espacio_publicitario();

-- ----------------------------------------------------------------------------
-- 5. TRIGGERS SOBRE TABLA: espacio_publicitario
-- ----------------------------------------------------------------------------

-- Trigger 9: Revalidación en cascada de las funciones que usan el espacio modificado
DROP TRIGGER IF EXISTS trg_espacio_propagar_a_funciones ON espacio_publicitario;
CREATE TRIGGER trg_espacio_propagar_a_funciones
AFTER UPDATE OF duracion_seg, clasificacion
ON espacio_publicitario
FOR EACH ROW
WHEN (OLD.duracion_seg IS DISTINCT FROM NEW.duracion_seg
      OR OLD.clasificacion IS DISTINCT FROM NEW.clasificacion)
EXECUTE FUNCTION fn_propagar_espacio_a_funciones();

