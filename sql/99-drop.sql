-- ============================================================================
-- PROYECTO: Automatización e Integridad Transaccional en PostgreSQL
-- CASO: Cadena de Cines Sunstar — Motor Relacional y Reglas de Negocio
-- ARCHIVO: sql/99-drop.sql
-- DESCRIPCIÓN: Limpieza controlada en cascada inversa de todos los objetos
--              del esquema (tablas, dominios, tipos y extensiones).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. ELIMINACIÓN DE VISTAS
-- ----------------------------------------------------------------------------

DROP VIEW IF EXISTS v_limpieza_por_sala;
DROP VIEW IF EXISTS v_gerente_por_sucursal;
DROP VIEW IF EXISTS v_publicidad_por_funcion;
DROP VIEW IF EXISTS v_programacion;

-- ----------------------------------------------------------------------------
-- 1. ELIMINACIÓN DE TABLAS (Orden inverso de dependencias referenciales)
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS limpia_la CASCADE;
DROP TABLE IF EXISTS compra_la CASCADE;
DROP TABLE IF EXISTS administra_la CASCADE;
DROP TABLE IF EXISTS trabaja_en CASCADE;
DROP TABLE IF EXISTS compra_en CASCADE;
DROP TABLE IF EXISTS provee CASCADE;
DROP TABLE IF EXISTS vende CASCADE;

DROP TABLE IF EXISTS entrada CASCADE;
DROP TABLE IF EXISTS proyeccion CASCADE;
DROP TABLE IF EXISTS funcion CASCADE;
DROP TABLE IF EXISTS cartelera CASCADE;

DROP TABLE IF EXISTS compone CASCADE;
DROP TABLE IF EXISTS espacio_publicitario CASCADE;
DROP TABLE IF EXISTS publicidad CASCADE;
DROP TABLE IF EXISTS pelicula CASCADE;

DROP TABLE IF EXISTS cliente CASCADE;
DROP TABLE IF EXISTS articulo CASCADE;
DROP TABLE IF EXISTS proveedor CASCADE;
DROP TABLE IF EXISTS kiosko CASCADE;
DROP TABLE IF EXISTS sala CASCADE;
DROP TABLE IF EXISTS empleado CASCADE;
DROP TABLE IF EXISTS sucursal CASCADE;

-- ----------------------------------------------------------------------------
-- 2. ELIMINACIÓN DE FUNCIONES PL/pgSQL
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS fn_validar_cartelera_publicable(integer) CASCADE;
DROP FUNCTION IF EXISTS fn_validar_clasificacion_espacio_pelicula() CASCADE;
DROP FUNCTION IF EXISTS fn_propagar_espacio_a_funciones() CASCADE;
DROP FUNCTION IF EXISTS fn_recalcular_espacio_publicitario() CASCADE;
DROP FUNCTION IF EXISTS fn_validar_numero_asiento() CASCADE;
DROP FUNCTION IF EXISTS fn_validar_sucursal_proyeccion() CASCADE;
DROP FUNCTION IF EXISTS fn_validar_compatibilidad_sala() CASCADE;
DROP FUNCTION IF EXISTS fn_actualizar_rango_proyecciones_de_funcion() CASCADE;
DROP FUNCTION IF EXISTS fn_sincronizar_rango_proyeccion() CASCADE;
DROP FUNCTION IF EXISTS fn_calcular_fin_funcion() CASCADE;
DROP FUNCTION IF EXISTS fn_peso_clasificacion(clasificacion_pelicula) CASCADE;

-- ----------------------------------------------------------------------------
-- 3. ELIMINACIÓN DE DOMINIOS
-- ----------------------------------------------------------------------------

DROP DOMAIN IF EXISTS ean13 CASCADE;
DROP DOMAIN IF EXISTS email CASCADE;

-- ----------------------------------------------------------------------------
-- 4. ELIMINACIÓN DE TIPOS ENUMERADOS
-- ----------------------------------------------------------------------------

DROP TYPE IF EXISTS tipo_entrada CASCADE;
DROP TYPE IF EXISTS tipo_publicidad CASCADE;
DROP TYPE IF EXISTS clasificacion_pelicula CASCADE;
DROP TYPE IF EXISTS tipo_sala CASCADE;
DROP TYPE IF EXISTS tipo_empleado CASCADE;

-- ----------------------------------------------------------------------------
-- 5. EXTENSIONES
-- ----------------------------------------------------------------------------
-- Se mantiene btree_gist si se utiliza en la base de datos o se elimina limpiamente:
DROP EXTENSION IF EXISTS btree_gist CASCADE;
DROP EXTENSION IF EXISTS dblink CASCADE; -- Usada solo por tests/03-concurrencia.sql

-- ----------------------------------------------------------------------------
-- 6. CONFIGURACIÓN DE BASE DE DATOS
-- ----------------------------------------------------------------------------
-- Revierte la zona horaria fijada en 01-schema.sql
DO $$
BEGIN
    EXECUTE format('ALTER DATABASE %I RESET timezone', current_database());
END $$;

