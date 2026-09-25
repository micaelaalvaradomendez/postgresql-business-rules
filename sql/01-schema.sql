-- ============================================================================
-- PROYECTO: Automatización e Integridad Transaccional en PostgreSQL
-- CASO: Cadena de Cines Sunstar — Motor Relacional y Reglas de Negocio
-- ARCHIVO: sql/01-schema.sql
-- DESCRIPCIÓN: Esquema normalizado en 3FN, extensiones, dominios, tablas,
--              claves compuestas y restricciones declarativas avanzadas (GiST).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. EXTENSIONES REQUERIDAS
-- ----------------------------------------------------------------------------
-- btree_gist permite combinar operadores de igualdad (=) con operadores de
-- solapamiento de rangos (&&) en restricciones de exclusión EXCLUDE USING gist.
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ----------------------------------------------------------------------------
-- 1.1 ZONA HORARIA OPERATIVA
-- ----------------------------------------------------------------------------
-- Los TIMESTAMPTZ se almacenan internamente en UTC; la zona horaria solo define
-- cómo se interpretan los literales sin offset y cómo se presentan los resultados.
-- Se fija a nivel base de datos (sesiones futuras) y en la sesión actual (seed).
DO $$
BEGIN
    EXECUTE format('ALTER DATABASE %I SET timezone TO %L',
                   current_database(), 'America/Argentina/Buenos_Aires');
END $$;

SET timezone TO 'America/Argentina/Buenos_Aires';

-- ----------------------------------------------------------------------------
-- 2. TIPOS ENUMERADOS Y DOMINIOS
-- ----------------------------------------------------------------------------

CREATE TYPE tipo_empleado AS ENUM (
    'gerente',
    'limpieza',
    'atencion_al_cliente'
);

CREATE TYPE tipo_sala AS ENUM (
    '2D',
    '3D',
    'IMAX'
);

CREATE TYPE clasificacion_pelicula AS ENUM (
    'ATP',
    'P-13',
    'P-16',
    'P-18',
    'P-21'
);

CREATE TYPE tipo_publicidad AS ENUM (
    'trailer',
    'publicidad_negocio',
    'promocion_sucursal'
);

CREATE TYPE tipo_entrada AS ENUM (
    'kiosko',
    'online'
);

-- Dominio para correos electrónicos con validación estricta por expresión regular
CREATE DOMAIN email AS VARCHAR(255)
    CHECK (VALUE ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

-- Dominio para códigos de barras estándar EAN-13 (13 dígitos numéricos)
CREATE DOMAIN ean13 AS BIGINT
    CHECK (VALUE BETWEEN 0 AND 9999999999999);

-- ----------------------------------------------------------------------------
-- 3. ENTIDADES MAESTRAS (CATÁLOGOS Y ESTRUCTURA ORGANIZACIONAL)
-- ----------------------------------------------------------------------------

-- SUCURSAL: Sedes físicas del complejo cinematográfico
CREATE TABLE sucursal (
    id_sucursal      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre           VARCHAR(50) NOT NULL UNIQUE CHECK (nombre <> ''),
    telefono         VARCHAR(25),
    ciudad           VARCHAR(40) NOT NULL,
    calle            VARCHAR(60) NOT NULL,
    numero_de_calle  SMALLINT NOT NULL CHECK (numero_de_calle > 0)
);

-- EMPLEADO: Personal operativo y administrativo por sucursal
CREATE TABLE empleado (
    legajo         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dni            INTEGER NOT NULL UNIQUE CHECK (dni > 0),
    id_sucursal    INTEGER NOT NULL REFERENCES sucursal(id_sucursal)
                   ON UPDATE CASCADE ON DELETE RESTRICT,
    empleado       tipo_empleado NOT NULL,
    nombre         VARCHAR(40) NOT NULL,
    apellido       VARCHAR(40) NOT NULL,
    telefono       VARCHAR(25) NOT NULL,
    mail           email NOT NULL,
    calle          VARCHAR(60) NOT NULL,
    numero         SMALLINT NOT NULL CHECK (numero > 0),
    codigo_postal  VARCHAR(10)
);

-- Regla de Negocio R-08: Cada sucursal cuenta con exactamente un único gerente activo.
CREATE UNIQUE INDEX empleado_gerente_por_sucursal_uidx
ON empleado(id_sucursal)
WHERE empleado = 'gerente';

-- SALA: Espacio físico de exhibición con tecnología y aforo delimitado
CREATE TABLE sala (
    nro_sala       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_sucursal    INTEGER NOT NULL REFERENCES sucursal(id_sucursal)
                   ON UPDATE CASCADE ON DELETE CASCADE,
    cant_asientos  SMALLINT NOT NULL CHECK (cant_asientos > 0),
    sala           tipo_sala NOT NULL
);

-- KIOSKO: Área de venta de golosinas y snacks (uno solo por sucursal)
CREATE TABLE kiosko (
    id_kiosko    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_sucursal  INTEGER NOT NULL UNIQUE REFERENCES sucursal(id_sucursal)
                 ON UPDATE CASCADE ON DELETE CASCADE
);

-- PROVEEDOR: Empresas abastecedoras de artículos
CREATE TABLE proveedor (
    id_proveedor  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cuit          BIGINT NOT NULL UNIQUE CHECK (cuit > 0),
    mail          email NOT NULL,
    nombre        VARCHAR(60) NOT NULL,
    descripcion   VARCHAR(120)
);

-- ARTÍCULO: Bienes comercializados en los kioskos con precio monetario exacto
CREATE TABLE articulo (
    id_articulo  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo       ean13 NOT NULL UNIQUE,
    nombre       VARCHAR(60) NOT NULL,
    precio       NUMERIC(10,2) NOT NULL CHECK (precio > 0)
);

-- CLIENTE: Compradores registrados para entradas o compras en kiosko
CREATE TABLE cliente (
    id_cliente  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dni         INTEGER NOT NULL UNIQUE CHECK (dni > 0),
    mail        email NOT NULL
);

-- ----------------------------------------------------------------------------
-- 4. PROGRAMACIÓN, CONTENIDOS Y ESPACIOS PUBLICITARIOS
-- ----------------------------------------------------------------------------

-- PELÍCULA: Títulos disponibles con su duración en minutos y restricción etaria
CREATE TABLE pelicula (
    codigo_pelicula  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    titulo           VARCHAR(80) NOT NULL UNIQUE CHECK (titulo <> ''),
    genero           VARCHAR(30),
    trailer_min      SMALLINT NOT NULL DEFAULT 2 CHECK (trailer_min > 0),
    sinopsis         TEXT CHECK (sinopsis <> ''),
    duracion_min     SMALLINT NOT NULL CHECK (duracion_min > 0),
    clasificacion    clasificacion_pelicula NOT NULL
);

-- PUBLICIDAD: Piezas individuales (trailers, publicidad comercial, promociones)
CREATE TABLE publicidad (
    id_publicidad  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    duracion_seg   INTEGER NOT NULL CHECK (duracion_seg > 0),
    clasificacion  clasificacion_pelicula NOT NULL,
    publicidad     tipo_publicidad NOT NULL
);

-- ESPACIO PUBLICITARIO: Bloque proyectado antes del inicio de la película
CREATE TABLE espacio_publicitario (
    cod_espacio_publicitario  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    duracion_seg              INTEGER NOT NULL DEFAULT 0 CHECK (duracion_seg >= 0),
    clasificacion             clasificacion_pelicula NOT NULL DEFAULT 'ATP'
);

-- COMPONE: Relación N:M entre un espacio publicitario y sus piezas
CREATE TABLE compone (
    cod_espacio_publicitario  INTEGER NOT NULL REFERENCES espacio_publicitario(cod_espacio_publicitario)
                              ON UPDATE CASCADE ON DELETE CASCADE,
    cod_publicidad            INTEGER NOT NULL REFERENCES publicidad(id_publicidad)
                              ON UPDATE CASCADE ON DELETE CASCADE,
    PRIMARY KEY (cod_espacio_publicitario, cod_publicidad)
);

-- CARTELERA: Período de programación semanal propio de cada sucursal
CREATE TABLE cartelera (
    codigo_cartelera  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_sucursal       INTEGER NOT NULL REFERENCES sucursal(id_sucursal)
                      ON UPDATE CASCADE ON DELETE CASCADE,
    fecha_inicio      DATE NOT NULL,
    fecha_fin         DATE NOT NULL,
    CONSTRAINT cartelera_fechas_orden_ck CHECK (fecha_fin >= fecha_inicio),
    -- Regla de Negocio: Una sucursal no puede tener dos períodos de cartelera solapados
    CONSTRAINT cartelera_sucursal_periodo_excl EXCLUDE USING gist (
        id_sucursal WITH =,
        daterange(fecha_inicio, fecha_fin, '[]') WITH &&
    )
);

-- FUNCIÓN: Instancia de programación conceptual (película + horario + versión + publicidad)
CREATE TABLE funcion (
    id_funcion                INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo_pelicula           INTEGER NOT NULL REFERENCES pelicula(codigo_pelicula)
                              ON UPDATE CASCADE ON DELETE RESTRICT,
    codigo_cartelera          INTEGER NOT NULL REFERENCES cartelera(codigo_cartelera)
                              ON UPDATE CASCADE ON DELETE CASCADE,
    cod_espacio_publicitario  INTEGER REFERENCES espacio_publicitario(cod_espacio_publicitario)
                              ON UPDATE CASCADE ON DELETE SET NULL,
    tipo_pelicula             tipo_sala NOT NULL,
    idioma                    VARCHAR(30) NOT NULL CHECK (idioma <> ''),
    fecha_hora_inicio         TIMESTAMPTZ NOT NULL,
    duracion_total_min        INTEGER NOT NULL DEFAULT 0 CHECK (duracion_total_min >= 0),
    fecha_hora_fin            TIMESTAMPTZ NOT NULL,
    CONSTRAINT funcion_intervalo_ck CHECK (fecha_hora_fin > fecha_hora_inicio)
);

-- ----------------------------------------------------------------------------
-- 5. ASIGNACIÓN FÍSICA Y CONTROL DE CONCURRENCIA (GiST)
-- ----------------------------------------------------------------------------

-- PROYECCIÓN: Asignación de una función conceptual a una sala física determinada.
-- Una misma función puede exhibirse en múltiples salas simultáneamente.
CREATE TABLE proyeccion (
    nro_sala         INTEGER NOT NULL REFERENCES sala(nro_sala)
                     ON UPDATE CASCADE ON DELETE RESTRICT,
    id_funcion       INTEGER NOT NULL REFERENCES funcion(id_funcion)
                     ON UPDATE CASCADE ON DELETE CASCADE,
    rango_ocupacion  TSTZRANGE NOT NULL,
    PRIMARY KEY (nro_sala, id_funcion),
    -- Regla de Negocio R-01 (Crítica):
    -- Exclusión declarativa de solapamiento temporal por sala física.
    -- Evita condiciones de carrera sin requerir bloqueos pesados en la capa de aplicación.
    CONSTRAINT proyeccion_sin_solapamiento EXCLUDE USING gist (
        nro_sala WITH =,
        rango_ocupacion WITH &&
    )
);

COMMENT ON TABLE proyeccion IS 
'Asignación física de funciones a salas con rango temporal de ocupación [inicio, fin)';

COMMENT ON CONSTRAINT proyeccion_sin_solapamiento ON proyeccion IS 
'Garantiza a nivel motor mediante GiST que una sala física no proyecte dos funciones solapadas en el tiempo';

-- ----------------------------------------------------------------------------
-- 6. TRANSACCIÓN DE VENTA Y PREVENCIÓN DE OVERBOOKING
-- ----------------------------------------------------------------------------

-- ENTRADA: Ticket emitido vinculado obligatoriamente a una proyección concreta
CREATE TABLE entrada (
    codigo         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nro_sala       INTEGER NOT NULL,
    id_funcion     INTEGER NOT NULL,
    nro_asiento    INTEGER NOT NULL CHECK (nro_asiento > 0),
    tipo_entrada   tipo_entrada NOT NULL,
    precio         NUMERIC(10,2) NOT NULL CHECK (precio >= 0),
    fecha_emision  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT entrada_proyeccion_fk FOREIGN KEY (nro_sala, id_funcion)
        REFERENCES proyeccion(nro_sala, id_funcion)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    -- Regla de Negocio R-02 (Crítica):
    -- Un asiento físico no puede venderse dos veces para la misma proyección física
    CONSTRAINT entrada_asiento_unico UNIQUE (nro_sala, id_funcion, nro_asiento)
);

COMMENT ON TABLE entrada IS 
'Entradas emitidas asociadas a la proyección en sala física y butaca asignada';

COMMENT ON CONSTRAINT entrada_asiento_unico ON entrada IS 
'Garantiza atomicidad transaccional: previene overbooking y colisiones de asientos bajo concurrencia';

-- ----------------------------------------------------------------------------
-- 7. RELACIONES AUXILIARES Y OPERATIVAS
-- ----------------------------------------------------------------------------

-- Artículos que comercializa cada kiosko
CREATE TABLE vende (
    id_kiosko    INTEGER NOT NULL REFERENCES kiosko(id_kiosko)
                 ON UPDATE CASCADE ON DELETE CASCADE,
    id_articulo  INTEGER NOT NULL REFERENCES articulo(id_articulo)
                 ON UPDATE CASCADE ON DELETE RESTRICT,
    PRIMARY KEY (id_kiosko, id_articulo)
);

-- Proveedores asignados a cada kiosko
CREATE TABLE provee (
    id_proveedor  INTEGER NOT NULL REFERENCES proveedor(id_proveedor)
                  ON UPDATE CASCADE ON DELETE RESTRICT,
    id_kiosko     INTEGER NOT NULL REFERENCES kiosko(id_kiosko)
                  ON UPDATE CASCADE ON DELETE CASCADE,
    PRIMARY KEY (id_proveedor, id_kiosko)
);

-- Compras en kiosko efectuadas por clientes
CREATE TABLE compra_en (
    id_compra_kiosko  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_kiosko         INTEGER NOT NULL REFERENCES kiosko(id_kiosko)
                      ON UPDATE CASCADE ON DELETE CASCADE,
    id_cliente        INTEGER NOT NULL REFERENCES cliente(id_cliente)
                      ON UPDATE CASCADE ON DELETE RESTRICT,
    fecha_compra      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Personal de atención asignado a kiosko
CREATE TABLE trabaja_en (
    id_empleado  INTEGER NOT NULL REFERENCES empleado(legajo)
                 ON UPDATE CASCADE ON DELETE CASCADE,
    id_kiosko    INTEGER NOT NULL REFERENCES kiosko(id_kiosko)
                 ON UPDATE CASCADE ON DELETE CASCADE,
    PRIMARY KEY (id_empleado, id_kiosko)
);

-- Gerentes que administran la programación de la función
CREATE TABLE administra_la (
    id_empleado  INTEGER NOT NULL REFERENCES empleado(legajo)
                 ON UPDATE CASCADE ON DELETE RESTRICT,
    id_funcion   INTEGER NOT NULL REFERENCES funcion(id_funcion)
                 ON UPDATE CASCADE ON DELETE CASCADE,
    PRIMARY KEY (id_empleado, id_funcion)
);

-- Relación de compra de entradas por clientes
CREATE TABLE compra_la (
    id_cliente    INTEGER NOT NULL REFERENCES cliente(id_cliente)
                  ON UPDATE CASCADE ON DELETE RESTRICT,
    id_entrada    INTEGER NOT NULL UNIQUE REFERENCES entrada(codigo)
                  ON UPDATE CASCADE ON DELETE RESTRICT,
    fecha_compra  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_cliente, id_entrada)
);

-- Asignación de salas para personal de limpieza
CREATE TABLE limpia_la (
    id_empleado  INTEGER NOT NULL REFERENCES empleado(legajo)
                 ON UPDATE CASCADE ON DELETE CASCADE,
    nro_sala     INTEGER NOT NULL REFERENCES sala(nro_sala)
                 ON UPDATE CASCADE ON DELETE CASCADE,
    PRIMARY KEY (id_empleado, nro_sala)
);

