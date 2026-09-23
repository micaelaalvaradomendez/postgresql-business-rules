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

-- Trigger 1: Cálculo automático de fecha_hora_fin antes de persistir la función
DROP TRIGGER IF EXISTS trg_funcion_calcular_fin ON funcion;
CREATE TRIGGER trg_funcion_calcular_fin
BEFORE INSERT OR UPDATE OF fecha_hora_inicio, codigo_pelicula, cod_espacio_publicitario
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

-- Trigger 3: Propagación de modificaciones horarias a las proyecciones en sala física
DROP TRIGGER IF EXISTS trg_funcion_propagar_horario ON funcion;
CREATE TRIGGER trg_funcion_propagar_horario
AFTER UPDATE OF fecha_hora_inicio, fecha_hora_fin
ON funcion
FOR EACH ROW
EXECUTE FUNCTION fn_actualizar_rango_proyecciones_de_funcion();

-- ----------------------------------------------------------------------------
-- 2. TRIGGERS SOBRE TABLA: proyeccion
-- ----------------------------------------------------------------------------

-- Trigger 4: Auto-población de rango_ocupacion si se omite en la inserción
DROP TRIGGER IF EXISTS trg_proyeccion_sincronizar_rango ON proyeccion;
CREATE TRIGGER trg_proyeccion_sincronizar_rango
BEFORE INSERT
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

