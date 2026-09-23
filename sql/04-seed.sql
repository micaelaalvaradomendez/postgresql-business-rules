-- ============================================================================
-- PROYECTO: Automatización e Integridad Transaccional en PostgreSQL
-- CASO: Cadena de Cines Sunstar — Motor Relacional y Reglas de Negocio
-- ARCHIVO: sql/04-seed.sql
-- DESCRIPCIÓN: Datos sintéticos consistentes, trazables e independientes de
--              IDs fijos asumidos. Demuestra escenarios de negocio clave.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. SUCURSALES (Sedes del complejo)
-- ----------------------------------------------------------------------------
INSERT INTO sucursal (nombre, telefono, ciudad, calle, numero_de_calle)
VALUES
    ('Sunstar Shopping Abasto', '011-4861-1000', 'Buenos Aires', 'Avenida Corrientes', 3247),
    ('Sunstar Rosario Centro',  '0341-420-2000', 'Rosario',       'Peatonal Córdoba',   1450),
    ('Sunstar Córdoba Mall',    '0351-470-3000', 'Córdoba',       'Duarte Quirós',      1400);

-- ----------------------------------------------------------------------------
-- 2. EMPLEADOS (1 Gerente por sucursal + personal operativo)
-- ----------------------------------------------------------------------------
-- Demuestra el índice único parcial: exactamente UN gerente activo por sucursal.
INSERT INTO empleado (dni, id_sucursal, empleado, nombre, apellido, telefono, mail, calle, numero, codigo_postal)
VALUES
    -- Gerentes (1 por sede)
    (28111222, (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto'),
     'gerente', 'Martín', 'Palermo', '011-5555-0101', 'martin.palermo@sunstar.com', 'Av. Santa Fe', 2100, 'C1425'),
    (29333444, (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Rosario Centro'),
     'gerente', 'Luciana', 'Aymar', '0341-555-0202', 'luciana.aymar@sunstar.com', 'Bv. Oroño', 850, 'S2000'),
    (30555666, (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Córdoba Mall'),
     'gerente', 'David', 'Nalbandian', '0351-555-0303', 'david.nalbandian@sunstar.com', 'Av. Colón', 1200, 'X5000'),

    -- Personal de atención al cliente (Kiosko y taquilla)
    (35123456, (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto'),
     'atencion_al_cliente', 'Facundo', 'Gómez', '011-5555-0404', 'facundo.gomez@sunstar.com', 'Lavalle', 1500, 'C1048'),
    (36234567, (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto'),
     'atencion_al_cliente', 'Camila', 'Torres', '011-5555-0505', 'camila.torres@sunstar.com', 'Tucumán', 1800, 'C1050'),
    (37345678, (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Rosario Centro'),
     'atencion_al_cliente', 'Franco', 'Ríos', '0341-555-0606', 'franco.rios@sunstar.com', 'San Lorenzo', 1100, 'S2000'),
    (38456789, (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Córdoba Mall'),
     'atencion_al_cliente', 'Julieta', 'Pérez', '0351-555-0707', 'julieta.perez@sunstar.com', 'Ituzaingó', 450, 'X5000'),

    -- Personal de limpieza
    (39567890, (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto'),
     'limpieza', 'Esteban', 'Quito', '011-5555-0808', 'esteban.quito@sunstar.com', 'Sarmiento', 2200, 'C1044'),
    (40678901, (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto'),
     'limpieza', 'Romina', 'Vargas', '011-5555-0909', 'romina.vargas@sunstar.com', 'Anchorena', 650, 'C1170'),
    (41789012, (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Rosario Centro'),
     'limpieza', 'Joaquín', 'Díaz', '0341-555-1010', 'joaquin.diaz@sunstar.com', 'Mitre', 900, 'S2000'),
    (42890123, (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Córdoba Mall'),
     'limpieza', 'Silvia', 'Molina', '0351-555-1111', 'silvia.molina@sunstar.com', 'Chacabuco', 300, 'X5000');

-- ----------------------------------------------------------------------------
-- 3. SALAS DE CINE (Diversidad tecnológica y aforos)
-- ----------------------------------------------------------------------------
INSERT INTO sala (id_sucursal, cant_asientos, sala)
VALUES
    -- Sede Abasto: 4 salas (2D, 3D, IMAX, 2D)
    ((SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto'), 120, '2D'),   -- Sala 1
    ((SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto'), 150, '3D'),   -- Sala 2
    ((SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto'), 200, 'IMAX'), -- Sala 3
    ((SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto'), 90,  '2D'),   -- Sala 4

    -- Sede Rosario: 2 salas (2D, 3D)
    ((SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Rosario Centro'),  100, '2D'),   -- Sala 5
    ((SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Rosario Centro'),  140, '3D'),   -- Sala 6

    -- Sede Córdoba: 2 salas (2D, 3D)
    ((SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Córdoba Mall'),    110, '2D'),   -- Sala 7
    ((SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Córdoba Mall'),    160, '3D');   -- Sala 8

-- ----------------------------------------------------------------------------
-- 4. KIOSKOS (Uno por cada sucursal)
-- ----------------------------------------------------------------------------
INSERT INTO kiosko (id_sucursal)
VALUES
    ((SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto')),
    ((SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Rosario Centro')),
    ((SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Córdoba Mall'));

-- ----------------------------------------------------------------------------
-- 5. PROVEEDORES Y ARTÍCULOS DE KIOSKO
-- ----------------------------------------------------------------------------
INSERT INTO proveedor (cuit, mail, nombre, descripcion)
VALUES
    (30711223344, 'ventas@snackspop.com.ar',     'Snacks Pop Argentina',      'Maíz pisingallo, aceites y saborizantes'),
    (30722334455, 'contacto@bebidasdelsur.com',  'Distribuidora Bebidas Sur', 'Gaseosas, aguas saborizadas y energizantes'),
    (30733445566, 'pedidos@dulcesgolocine.com',  'GoloCine Golosinas',        'Chocolates, gomitas y confites premium');

INSERT INTO articulo (codigo, nombre, precio)
VALUES
    (7791234567890, 'Balde Popcorn Salado Grande',   6500.00),
    (7791234567891, 'Balde Popcorn Dulce Mediano',   5200.00),
    (7791234567892, 'Gaseosa Primera Marca 1 Litro', 4200.00),
    (7791234567893, 'Bandeja de Nachos con Cheddar', 5800.00),
    (7791234567894, 'Agua Mineral sin Gas 500ml',    2800.00),
    (7791234567895, 'Combo Mega Pareja (2 Pop + 2 Gas)', 14500.00);

-- Vinculación de artículos a kioskos
INSERT INTO vende (id_kiosko, id_articulo)
SELECT k.id_kiosko, a.id_articulo
FROM kiosko k
CROSS JOIN articulo a;

-- Vinculación de proveedores a kioskos
INSERT INTO provee (id_proveedor, id_kiosko)
SELECT p.id_proveedor, k.id_kiosko
FROM proveedor p
CROSS JOIN kiosko k;

-- ----------------------------------------------------------------------------
-- 6. CLIENTES
-- ----------------------------------------------------------------------------
INSERT INTO cliente (dni, mail)
VALUES
    (32111001, 'marina.salvatierra@gmail.com'),
    (33222002, 'rodrigo.benitez@hotmail.com'),
    (34333003, 'valeria.gutierrez@yahoo.com.ar'),
    (35444004, 'pablo.marmol@outlook.com'),
    (36555005, 'laura.castro@gmail.com');

-- ----------------------------------------------------------------------------
-- 7. PELÍCULAS
-- ----------------------------------------------------------------------------
INSERT INTO pelicula (titulo, genero, trailer_min, sinopsis, duracion_min, clasificacion)
VALUES
    ('Toy Story 5',
     'Animación', 2, 'Woody y Buzz regresan en una aventura nostálgica para toda la familia.',
     100, 'ATP'),

    ('Dune: Parte Dos',
     'Ciencia Ficción', 3, 'Paul Atreides se une a Chani y a los Fremen para buscar venganza.',
     166, 'P-13'),

    ('Inception: El Origen',
     'Ciencia Ficción', 3, 'Un ladrón que roba secretos a través de la tecnología de compartir sueños.',
     148, 'P-13'),

    ('Oppenheimer',
     'Drama Histórico', 3, 'La historia del físico estadounidense J. Robert Oppenheimer y el proyecto Manhattan.',
     180, 'P-16'),

    ('El Conjuro 4: Ritos Finales',
     'Terror', 2, 'Los Warren enfrentan su caso paranormal más siniestro y letal.',
     112, 'P-18');

-- ----------------------------------------------------------------------------
-- 8. PUBLICIDADES Y ESPACIOS PUBLICITARIOS
-- ----------------------------------------------------------------------------
INSERT INTO publicidad (duracion_seg, clasificacion, publicidad)
VALUES
    -- Trailers
    (120, 'ATP',  'trailer'),             -- 1: Trailer película infantil
    (150, 'P-13', 'trailer'),             -- 2: Trailer acción
    (140, 'P-16', 'trailer'),             -- 3: Trailer thriller
    (160, 'P-18', 'trailer'),             -- 4: Trailer terror adulto

    -- Publicidades de negocio
    (45,  'ATP',  'publicidad_negocio'),  -- 5: Gaseosa
    (30,  'ATP',  'publicidad_negocio'),  -- 6: Banco y beneficios

    -- Promociones de sucursal
    (60,  'ATP',  'promocion_sucursal'),  -- 7: Descuento miércoles
    (45,  'ATP',  'promocion_sucursal');  -- 8: App Sunstar Club

-- Espacios publicitarios vacíos (los triggers calcularán duración y clasificación)
INSERT INTO espacio_publicitario (cod_espacio_publicitario)
OVERRIDING SYSTEM VALUE
VALUES (1), (2), (3);

-- Componer Espacio 1: Apto Todo Público (ATP)
-- Piezas: Trailer ATP (120s) + Publicidad Negocio (45s) + Promo Sucursal (60s) = 225 seg
INSERT INTO compone (cod_espacio_publicitario, cod_publicidad)
VALUES
    (1, 1),
    (1, 5),
    (1, 7);

-- Componer Espacio 2: Clasificación P-13
-- Piezas: Trailer P-13 (150s) + Publicidad Negocio (30s) + Promo Sucursal (45s) = 225 seg
INSERT INTO compone (cod_espacio_publicitario, cod_publicidad)
VALUES
    (2, 2),
    (2, 6),
    (2, 8);

-- Componer Espacio 3: Clasificación P-16
-- Piezas: Trailer P-16 (140s) + Publicidad Negocio (45s) + Promo Sucursal (60s) = 245 seg
INSERT INTO compone (cod_espacio_publicitario, cod_publicidad)
VALUES
    (3, 3),
    (3, 5),
    (3, 7);

-- ----------------------------------------------------------------------------
-- 9. CARTELERAS (Programación semanal por sucursal)
-- ----------------------------------------------------------------------------
INSERT INTO cartelera (id_sucursal, fecha_inicio, fecha_fin)
VALUES
    ((SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto'), '2026-10-15', '2026-10-21'),
    ((SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Rosario Centro'),  '2026-10-15', '2026-10-21'),
    ((SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Córdoba Mall'),    '2026-10-15', '2026-10-21');

-- ----------------------------------------------------------------------------
-- 10. FUNCIONES PROGRAMADAS
-- ----------------------------------------------------------------------------
-- El trigger trg_funcion_calcular_fin calcula de forma transparente
-- duracion_total_min y fecha_hora_fin en base a la película y el bloque publicitario.
INSERT INTO funcion (codigo_pelicula, codigo_cartelera, cod_espacio_publicitario, tipo_pelicula, idioma, fecha_hora_inicio, fecha_hora_fin)
VALUES
    -- Función 1: Toy Story 5 (ATP) en Cartelera Abasto, 14:00 hs
    ((SELECT codigo_pelicula FROM pelicula WHERE titulo = 'Toy Story 5'),
     (SELECT codigo_cartelera FROM cartelera WHERE id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto')),
     1, '2D', 'Español Latino', '2026-10-15 14:00:00-03', '2026-10-15 14:00:00-03'),

    -- Función 2: Dune: Parte Dos (P-13) en formato 3D en Cartelera Abasto, 16:30 hs
    ((SELECT codigo_pelicula FROM pelicula WHERE titulo = 'Dune: Parte Dos'),
     (SELECT codigo_cartelera FROM cartelera WHERE id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto')),
     2, '3D', 'Inglés Subtitulado', '2026-10-15 16:30:00-03', '2026-10-15 16:30:00-03'),

    -- Función 3: Inception (P-13) en formato IMAX en Cartelera Abasto, 14:00 hs
    -- Nótese: Comienza a la misma hora exacta que la Función 1 (14:00 hs), demostrando simultaneidad
    ((SELECT codigo_pelicula FROM pelicula WHERE titulo = 'Inception: El Origen'),
     (SELECT codigo_cartelera FROM cartelera WHERE id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto')),
     2, 'IMAX', 'Inglés Subtitulado', '2026-10-15 14:00:00-03', '2026-10-15 14:00:00-03'),

    -- Función 4: Toy Story 5 (ATP) — Función masiva popular, 17:00 hs
    -- Se exhibirá en Sala 1 y Sala 4 simultáneamente (Multi-sala)
    ((SELECT codigo_pelicula FROM pelicula WHERE titulo = 'Toy Story 5'),
     (SELECT codigo_cartelera FROM cartelera WHERE id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto')),
     1, '2D', 'Español Latino', '2026-10-15 17:00:00-03', '2026-10-15 17:00:00-03'),

    -- Función 5: Oppenheimer (P-16) en Cartelera Abasto, 20:00 hs
    ((SELECT codigo_pelicula FROM pelicula WHERE titulo = 'Oppenheimer'),
     (SELECT codigo_cartelera FROM cartelera WHERE id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto')),
     3, '2D', 'Inglés Subtitulado', '2026-10-15 20:00:00-03', '2026-10-15 20:00:00-03');

-- ----------------------------------------------------------------------------
-- 11. PROYECCIONES EN SALAS FÍSICAS
-- ----------------------------------------------------------------------------
-- El trigger trg_proyeccion_sincronizar_rango auto-completa rango_ocupacion
-- desde la función, validando compatibilidad de sala y sucursal.
INSERT INTO proyeccion (nro_sala, id_funcion, rango_ocupacion)
VALUES
    -- Función 1 (Toy Story 5) asignada a Sala 1 (2D Abasto) de 14:00 a 16:04
    ((SELECT nro_sala FROM sala WHERE cant_asientos = 120 AND id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto')),
     1, NULL),

    -- Función 2 (Dune 3D) asignada a Sala 2 (3D Abasto) de 16:30 a 19:40
    ((SELECT nro_sala FROM sala WHERE cant_asientos = 150 AND id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto')),
     2, NULL),

    -- Función 3 (Inception IMAX) asignada a Sala 3 (IMAX Abasto) de 14:00 a 16:52
    -- Horario simultáneo con Sala 1, pero sin colisión porque son salas físicas distintas
    ((SELECT nro_sala FROM sala WHERE cant_asientos = 200 AND id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto')),
     3, NULL),

    -- Función 4 (Toy Story 5 Multi-sala 17:00 a 19:04):
    -- Asignada a Sala 1 (consecutiva tras Función 1 que terminó 16:04)
    ((SELECT nro_sala FROM sala WHERE cant_asientos = 120 AND id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto')),
     4, NULL),

    -- Y a Sala 4 (90 asientos Abasto) simultáneamente:
    ((SELECT nro_sala FROM sala WHERE cant_asientos = 90 AND id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto')),
     4, NULL),

    -- Función 5 (Oppenheimer) asignada a Sala 1 tras Función 4
    ((SELECT nro_sala FROM sala WHERE cant_asientos = 120 AND id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto')),
     5, NULL);

-- ----------------------------------------------------------------------------
-- 12. EMISIÓN Y VENTA DE ENTRADAS
-- ----------------------------------------------------------------------------
-- Demuestra:
-- 1. Asientos válidos emitidos por proyección física.
-- 2. Asignación del mismo número de asiento en salas distintas para la misma función multi-sala.
INSERT INTO entrada (nro_sala, id_funcion, nro_asiento, tipo_entrada, precio)
VALUES
    -- Tickets para Función 1 en Sala 1
    ((SELECT nro_sala FROM proyeccion WHERE id_funcion = 1), 1, 1,  'online', 5500.00),
    ((SELECT nro_sala FROM proyeccion WHERE id_funcion = 1), 1, 2,  'online', 5500.00),
    ((SELECT nro_sala FROM proyeccion WHERE id_funcion = 1), 1, 15, 'kiosko', 5000.00),

    -- Tickets para Función 3 en Sala 3 (IMAX)
    ((SELECT nro_sala FROM proyeccion WHERE id_funcion = 3), 3, 50, 'online', 8500.00),
    ((SELECT nro_sala FROM proyeccion WHERE id_funcion = 3), 3, 51, 'online', 8500.00),

    -- DEMOSTRACIÓN CLAVE: Función 4 se proyecta en Sala 1 y Sala 4.
    -- Se vende el asiento 1 en Sala 1 y el asiento 1 en Sala 4.
    -- (En el esquema base original esto fallaba por UNIQUE(nro_asiento, id_funcion)).
    ((SELECT nro_sala FROM sala WHERE cant_asientos = 120 AND id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto')),
     4, 1, 'online', 5500.00),

    ((SELECT nro_sala FROM sala WHERE cant_asientos = 90 AND id_sucursal = (SELECT id_sucursal FROM sucursal WHERE nombre = 'Sunstar Shopping Abasto')),
     4, 1, 'kiosko', 5000.00);

-- Vinculación de entradas a clientes que las compraron
INSERT INTO compra_la (id_cliente, id_entrada)
VALUES
    ((SELECT id_cliente FROM cliente WHERE mail = 'marina.salvatierra@gmail.com'), 1),
    ((SELECT id_cliente FROM cliente WHERE mail = 'marina.salvatierra@gmail.com'), 2),
    ((SELECT id_cliente FROM cliente WHERE mail = 'rodrigo.benitez@hotmail.com'),  3),
    ((SELECT id_cliente FROM cliente WHERE mail = 'valeria.gutierrez@yahoo.com.ar'), 4),
    ((SELECT id_cliente FROM cliente WHERE mail = 'valeria.gutierrez@yahoo.com.ar'), 5),
    ((SELECT id_cliente FROM cliente WHERE mail = 'pablo.marmol@outlook.com'),     6),
    ((SELECT id_cliente FROM cliente WHERE mail = 'laura.castro@gmail.com'),       7);

-- ----------------------------------------------------------------------------
-- 13. ASIGNACIONES OPERATIVAS RESTANTES
-- ----------------------------------------------------------------------------
-- Personal de limpieza asignado a salas
INSERT INTO limpia_la (id_empleado, nro_sala)
VALUES
    ((SELECT legajo FROM empleado WHERE dni = 39567890), 1),
    ((SELECT legajo FROM empleado WHERE dni = 39567890), 2),
    ((SELECT legajo FROM empleado WHERE dni = 40678901), 3),
    ((SELECT legajo FROM empleado WHERE dni = 40678901), 4);

-- Gerente que administra la programación
INSERT INTO administra_la (id_empleado, id_funcion)
VALUES
    ((SELECT legajo FROM empleado WHERE dni = 28111222), 1),
    ((SELECT legajo FROM empleado WHERE dni = 28111222), 2),
    ((SELECT legajo FROM empleado WHERE dni = 28111222), 3),
    ((SELECT legajo FROM empleado WHERE dni = 28111222), 4),
    ((SELECT legajo FROM empleado WHERE dni = 28111222), 5);

