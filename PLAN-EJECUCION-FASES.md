# Plan Maestro de Ejecución por Fases — PostgreSQL Business Rules

> **Proyecto de Portafolio:** Caso 2 — Automatización e Integridad Transaccional en PostgreSQL  
> **Subtítulo:** *Normalización 3FN, Restricciones de Exclusión GiST y Lógica de Negocio en Motor con PL/pgSQL.*  
> **Dominio:** Cadena de Cines Sunstar  
> **Ubicación local:** `/home/micaela/postgresql-business-rules/`  
> **Repositorio remoto:** `https://github.com/micaelaalvaradomendez/postgresql-business-rules`  
> **Documento de referencia en portafolio:** `/home/micaela/cuaderno/emprendimiento/portafolio/caso-03-modelo-logica-bd-postgresql.md`

---

## 1. Misión y Alcance del Laboratorio

El objetivo de este proyecto es transformar una base de datos relacional académica en un **laboratorio de referencia profesional, reproducible y dockerizado**, que demuestre que:

> *"Las restricciones declarativas, extensiones especializadas (`btree_gist`) y funciones/triggers en PL/pgSQL pueden y deben garantizar las invariantes de negocio críticas a nivel motor, blindando la integridad de datos frente a condiciones de carrera (race conditions) y accesos concurrentes de múltiples microservicios."*

### Diagnóstico de Fallas del Esquema Base a Subsanar:
1. **Falla de integridad y overbooking en entradas:** La tabla `entrada` asociaba únicamente `(nro_asiento, id_funcion)`. Al permitir que una función se exhiba en varias salas simultáneamente (`proyecta`), impedía vender el mismo número de asiento en salas distintas y provocaba errores en tiempo de ejecución al validar asientos.
2. **Solapamiento temporal en salas físicas:** La entidad `horario` utilizaba el tipo `TIME` sin fecha ni zona horaria, imposibilitando garantizar que una sala no tenga funciones superpuestas entre días o en cruces de medianoche mediante exclusión GiST.
3. **Bloqueo circular (huevo y gallina) en Cartelera/Horario:** El trigger original exigía una función para insertar un horario, pero la función requería obligatoriamente un horario, forzando actualizaciones manuales posteriores con datos inconsistentes.
4. **Desincronización en eliminación de publicidad (`compone`):** Los triggers de duración y clasificación no contemplaban el evento `DELETE`, dejando métricas desactualizadas ante bajas de trailers o anuncios.
5. **Anti-patrones de diseño:** Tipos `float` para importes monetarios, atributos redundantes `id_empleado1` e `id_empleado2` en `trabaja_en`, y falta de vinculación entre `cartelera` y `sucursal`.
6. **Marcas académicas:** Referencias a "grupo 9" y entregas universitarias que deben ser sanitizadas para publicar un caso de ingeniería impecable.

---

## 2. Estructura de Destino del Repositorio

```text
postgresql-business-rules/
├── README.md                       # Documentación ejecutiva, DER y guía de uso rápido
├── LICENSE                         # Licencia MIT
├── Makefile                        # Orquestador: make up, make down, make reset, make test
├── docker-compose.yml              # PostgreSQL 16 Alpine con btree_gist
├── .gitignore                      # Exclusiones seguras
├── PLAN-EJECUCION-FASES.md         # Este documento maestro de trazabilidad
│
├── docs/
│   ├── modelo-conceptual.md        # Entidades, dominios, cardinalidades y diccionario
│   ├── reglas-de-negocio.md        # Matriz: Regla -> Objeto SQL -> Protección -> Prueba
│   ├── decisiones-tecnicas.md      # ADRs (GiST vs triggers, 3FN, solución overbooking)
│   └── migracion-del-modelo.md     # Bitácora de refactorización desde el modelo original
│
├── diagramas/
│   ├── der.puml                    # Código fuente PlantUML del Modelo Entidad-Relación
│   ├── der.png                     # Render gráfico de alta resolución para el README
│   └── flujo-reglas.puml           # Diagrama de secuencia/flujo de validación en motor
│
├── sql/
│   ├── 01-schema.sql               # Extensiones, tipos, dominios, tablas 3FN, PK/FK, CHECK y GiST
│   ├── 02-functions.sql            # Funciones PL/pgSQL con SECURITY INVOKER y control de excepciones
│   ├── 03-triggers.sql             # Triggers documentados vinculados a eventos del ciclo de vida
│   ├── 04-seed.sql                 # Datos sintéticos idempotentes y coherentes
│   └── 99-drop.sql                 # Script de limpieza limpia en cascada inversa
│
├── tests/
│   ├── 01-casos-positivos.sql      # Inserciones y flujos normales válidos
│   ├── 02-casos-negativos.sql      # Intentos de transacciones inválidas con aserción de ERRCODE
│   └── 03-concurrencia.sql         # Simulación de condiciones de carrera y venta simultánea
│
└── scripts/
    ├── init-db.sh                  # Inicialización automatizada del contenedor
    ├── reset-db.sh                 # Limpieza y recarga en caliente
    └── run-tests.sh                # Ejecutor de batería de pruebas con reporte coloreado
```

---

## 3. Fases de Desarrollo

### Fase 0: Inicialización del Laboratorio y Preservación del Origen
- [x] Crear estructura de directorios (`sql/`, `docs/`, `diagramas/`, `tests/`, `scripts/`).
- [x] Crear `.gitignore` profesional (ignorar dumps temporales, `.DS_Store`, etc.).
- [x] Crear `docs/migracion-del-modelo.md` documentando el inventario de partida y las transformaciones planeadas.
- [x] Mantener intactos los archivos base originales en la raíz (`sql ddl`, `sql insert`, `sql consultas`, `backup`, `modelo conceptual.drawio`, etc.) durante el proceso de migración.

### Fase 1: DDL Normalizado y Restricciones Declarativas (3FN)
- [x] Crear `sql/01-schema.sql`:
  - Habilitar extensión `btree_gist`.
  - Crear tipos enumerados (`tipo_empleado`, `tipo_sala`, `clasificacion_pelicula`, `tipo_publicidad`, `tipo_entrada`).
  - Crear dominios con validaciones regex (`email`, `ean13`).
  - Normalizar entidades principales:
    - `sucursal`: datos de sede y contacto.
    - `empleado`: legajo PK, DNI único, FK sucursal, índice parcial para gerente único por sucursal (`UNIQUE (id_sucursal) WHERE empleado = 'gerente'`).
    - `sala`: vinculada a sucursal, capacidad y tecnología (`tipo_sala`).
    - `kiosko`: un solo kiosko por sucursal (`UNIQUE (id_sucursal)`).
    - `articulo`: precios monetarios en `numeric(10,2)`.
    - `pelicula`: duraciones en minutos enteros (`integer`) o intervalos consistentes.
    - `publicidad`: duración y clasificación.
    - `espacio_publicitario`: duración acumulada y clasificación restrictiva.
    - `cartelera`: vinculada a `id_sucursal` con vigencia temporal (`fecha_inicio`, `fecha_fin`).
    - `funcion`: identificada por `id_funcion`, combinando película, cartelera, espacio publicitario, formato, idioma y fecha/hora de inicio.
    - `proyeccion`: tabla de asignación física `(nro_sala, id_funcion)` con `rango_ocupacion tstzrange` y restricción `EXCLUDE USING gist (nro_sala WITH =, rango_ocupacion WITH &&)`.
    - `entrada`: asociada a la proyección concreta `(nro_sala, id_funcion)` con restricción `UNIQUE (nro_sala, id_funcion, nro_asiento)` para evitar overbooking.
- [x] Crear `sql/99-drop.sql` para borrado limpio en orden inverso de dependencias.

### Fase 2: Lógica Procedural y Triggers PL/pgSQL
- [x] Crear `sql/02-functions.sql`:
  - `fn_calcular_fin_funcion()`: calcula `fecha_hora_fin` sumando duración de película, espacio publicitario y tiempo técnico de limpieza (20 min).
  - `fn_validar_compatibilidad_sala()`: valida que proyecciones 3D/IMAX solo se asignen a salas con equipamiento equivalente.
  - `fn_validar_sucursal_proyeccion()`: asegura que la sala física pertenezca a la misma sucursal que la cartelera de la función.
  - `fn_validar_numero_asiento()`: valida que el asiento solicitado exista dentro de la capacidad física de la sala asignada.
  - `fn_recalcular_espacio_publicitario()`: actualiza dinámicamente duración y clasificación ante `INSERT`, `UPDATE` o `DELETE` en `compone`.
  - `fn_validar_clasificacion_espacio_pelicula()`: comprueba que el espacio publicitario no tenga una clasificación superior a la de la película.
- [x] Crear `sql/03-triggers.sql` vinculando cada función a su evento correspondiente con convenciones estrictas y `SECURITY INVOKER`.

### Fase 3: Seed de Datos Coherente y Relacional
- [x] Crear `sql/04-seed.sql`:
  - Poblar sucursales reales ficticias.
  - Asignar empleados, roles y gerentes únicos.
  - Poblar salas con capacidades y tipos diferenciados.
  - Configurar películas de diversos géneros y clasificaciones.
  - Configurar publicidades y componer espacios publicitarios balanceados.
  - Programar carteleras y funciones que demuestren proyecciones simultáneas válidas y consecutivas.
  - Registrar ventas de entradas ordinarias.

### Fase 4: Batería de Pruebas Automatizadas
- [ ] Crear `tests/01-casos-positivos.sql`:
  - Multi-sala: una misma función proyectándose en 2 salas en paralelo.
  - Funciones consecutivas en la misma sala sin solapamiento.
  - Cálculo automático de horario de fin.
  - Recálculo de espacio publicitario ante inserción y borrado de anuncios.
- [ ] Crear `tests/02-casos-negativos.sql`:
  - Intento de solapamiento de horario en la misma sala $\to$ captura `exclusion_violation` (`ERRCODE 23P01`).
  - Intento de doble venta del mismo asiento en la misma proyección $\to$ captura `unique_violation` (`ERRCODE 23505`).
  - Asignación de película 3D en sala 2D $\to$ excepción de regla de negocio.
  - Asiento fuera de rango $\to$ excepción de regla de negocio.
  - Segundo gerente en la misma sucursal $\to$ excepción de índice único.
- [ ] Crear `tests/03-concurrencia.sql` con simulación transaccional.

### Fase 5: Dockerización y Automatización Local
- [ ] Crear `docker-compose.yml` con imagen `postgres:16-alpine`.
- [ ] Crear `Makefile` con comandos:
  - `make up`: Levanta el contenedor PostgreSQL.
  - `make down`: Detiene los servicios.
  - `make reset`: Limpia la base y reaplica schema, functions, triggers y seed.
  - `make test`: Ejecuta la suite de pruebas completa y reporta resultados.
  - `make psql`: Abre sesión interactiva en la base de datos.
- [ ] Crear `scripts/reset-db.sh` y `scripts/run-tests.sh`.

### Fase 6: Documentación Técnica, Diagramas y Sanitización
- [ ] Crear `diagramas/der.puml` con el modelo relacional completo.
- [ ] Generar imagen `diagramas/der.png`.
- [ ] Redactar `docs/modelo-conceptual.md`, `docs/reglas-de-negocio.md` y `docs/decisiones-tecnicas.md`.
- [ ] Redactar `README.md` final de alto impacto para el portafolio.
- [ ] Sanitizar archivos de origen (eliminar PDF universitario y referencias a materias antes del push final).

---

## 4. Criterio de Aceptación (Definición de Terminado)

El Caso 2 se considera completado y listo para vincular en el portafolio cuando:
1. `docker compose up -d` inicie PostgreSQL 16 sin intervención manual.
2. `make reset` ejecute en orden `01-schema.sql`, `02-functions.sql`, `03-triggers.sql` y `04-seed.sql` sin errores ni advertencias.
3. `make test` ejecute todas las pruebas positivas y negativas, verificando que los errores rechazados capturen exactamente los `ERRCODE` esperados.
4. El repositorio no contenga ningún rastro de nombres de docentes ni referencias a trabajos prácticos universitarios.
5. El `README.md` exponga el DER visual, la tesis técnica, la matriz de reglas y los snippets de código clave.

