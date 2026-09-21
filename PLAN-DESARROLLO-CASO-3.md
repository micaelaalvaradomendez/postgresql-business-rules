# Caso 3 - Plan de Desarrollo de PostgreSQL Business Rules

## Diseño y automatización de reglas de negocio en PostgreSQL

Este documento define el paso a paso para transformar la base de datos existente de la cadena de cines **Sunstar** en un caso profesional de ingeniería de bases de datos y lógica de negocio en PostgreSQL.

El punto de partida es el material migrado a este repositorio:

- `sql ddl`: esquema, tipos, dominios, tablas, claves, funciones y triggers.
- `sql insert`: datos de prueba y relaciones entre entidades.
- `sql consultas`: consultas operativas del dominio.
- `modelo conceptual.drawio`: modelo conceptual original.
- `Trabajo Practico Integrador - grupo  9.pdf`: descripción del universo del discurso.
- `backup`: respaldo de la base original.

El objetivo no es reemplazar el modelo relacional existente, sino llevarlo a un nivel reproducible, documentado y defendible técnicamente.

---

## 1. Objetivo profesional del caso

Construir un laboratorio reproducible en PostgreSQL que demuestre cómo el motor puede garantizar reglas de negocio críticas de una cadena de cines:

- Una cartelera pertenece a una sucursal y representa un período de programación.
- Una función combina una película, una cartelera, un horario, una versión de proyección, un idioma y un espacio publicitario.
- Una función puede proyectarse en varias salas al mismo tiempo.
- Varias funciones pueden comenzar a la misma hora dentro de una cartelera.
- Una misma sala nunca puede tener funciones superpuestas durante el mismo día.
- Un asiento no puede venderse dos veces para la misma función y sala.
- Una película 3D solo puede asignarse a una sala compatible.
- La duración final de una función se calcula automáticamente.
- El espacio publicitario debe ser compatible con la clasificación de la película.
- Las validaciones importantes deben estar protegidas por el motor y no depender únicamente de la aplicación.

La tesis técnica del repositorio será:

> Las relaciones, restricciones declarativas, funciones y triggers de PostgreSQL pueden expresar y proteger invariantes del dominio que deben mantenerse aunque existan varias aplicaciones, procesos o transacciones accediendo a la misma base.

---

## 2. Regla de modelado que debe mantenerse

La relación `PROYECTA(nro_sala, id_funcion)` es necesaria y debe conservarse.

Una función puede proyectarse en varias salas:

```text
Funcion 10 - Pelicula A - 16:00 - Espanol
    +-- Sala 1
    +-- Sala 2
```

También pueden existir varias funciones simultáneas dentro de una cartelera:

```text
Cartelera 1
    +-- Funcion 10 - Pelicula A - 16:00 - Sala 1
    +-- Funcion 11 - Pelicula B - 16:00 - Sala 2
    +-- Funcion 12 - Pelicula A - 16:00 - Sala 3
```

La restricción no debe ser `UNIQUE(codigo_cartelera, hora_inicio)`, porque impediría horarios simultáneos en salas distintas.

La regla correcta es:

> No pueden existir dos intervalos de funciones superpuestos para la misma sala y la misma fecha.

Una función repetida en varias salas es una sola función con varias filas en `PROYECTA`. Solo corresponde crear funciones distintas cuando cambia la programación relevante, por ejemplo el idioma, el tipo de proyección, el horario o la asignación conceptual de la función.

---

## 3. Resultado final esperado

La estructura final recomendada es:

```text
postgresql-business-rules/
├── README.md
├── PLAN-DESARROLLO-CASO-3.md
├── LICENSE
├── .gitignore
├── Makefile
├── docker-compose.yml
│
├── docs/
│   ├── modelo-conceptual.md
│   ├── reglas-de-negocio.md
│   ├── decisiones-tecnicas.md
│   └── migracion-del-modelo.md
│
├── diagrama/
│   ├── der.puml
│   ├── der.png
│   └── flujo-reglas.puml
│
├── sql/
│   ├── 01-schema.sql
│   ├── 02-functions.sql
│   ├── 03-triggers.sql
│   ├── 04-seed.sql
│   └── 99-drop.sql
│
├── tests/
│   ├── casos-positivos.sql
│   ├── casos-negativos.sql
│   ├── reglas-integridad.sql
│   └── concurrencia/
│       ├── sesion-a.sql
│       └── sesion-b.sql
│
└── scripts/
    ├── reset-db.sh
    └── run-tests.sh
```

Los archivos actuales se conservan como material de origen hasta completar la migración. No se deben eliminar ni sobrescribir durante la primera etapa.

---

# Fase 0 - Inventario y congelamiento del punto de partida

## Paso 0.1 - Registrar el origen

Documentar en `docs/migracion-del-modelo.md` qué contiene cada artefacto original:

- Modelo conceptual en Draw.io.
- DDL de tipos, dominios, tablas y triggers.
- Inserts de datos sintéticos.
- Consultas operativas.
- Backup de la base original.
- Descripción del universo del discurso.

## Paso 0.2 - Crear una copia de trabajo

No modificar directamente el archivo original `sql ddl`. Crear copias dentro de `sql/` y migrar de forma incremental.

La primera versión de trabajo debe poder compararse contra el origen para detectar qué cambió y por qué.

## Paso 0.3 - Definir el alcance

El caso debe concentrarse en tres ejes:

1. Programación de funciones y asignación de salas.
2. Venta segura de entradas y ocupación de asientos.
3. Composición y compatibilidad de espacios publicitarios.

El kiosko, empleados y proveedores permanecen en el modelo porque forman parte del universo, pero no deben desplazar el foco principal del caso.

---

# Fase 1 - Normalización del esquema existente

## Paso 1.1 - Separar los objetos SQL por responsabilidad

Dividir el contenido actual en archivos numerados:

- `01-schema.sql`: extensiones, tipos, dominios, tablas, PK, FK, `CHECK`, `UNIQUE` e índices.
- `02-functions.sql`: funciones PL/pgSQL reutilizables.
- `03-triggers.sql`: triggers asociados a reglas concretas.
- `04-seed.sql`: datos sintéticos consistentes.
- `99-drop.sql`: limpieza en orden inverso.

## Paso 1.2 - Uniformar nombres

Elegir una convención y aplicarla en todo el esquema. Se recomienda `snake_case` en minúsculas.

Resolver especialmente estas diferencias:

- `nro_sala` frente a `id_sala`.
- `cod_publicidad` frente a `id_publicidad`.
- `cod_espacio_publicitario` frente a `id_espacio_publicitario`.
- `kiosko` frente a `kiosco`.
- `compone` aparece repetida en la documentación de relaciones.

La documentación y el SQL deben utilizar exactamente los mismos nombres.

## Paso 1.3 - Revisar claves candidatas

Conservar las claves primarias artificiales cuando faciliten las referencias, pero declarar las reglas de unicidad reales:

- `VENDE`: `UNIQUE(id_kiosko, id_articulo)`.
- `PROYECTA`: `PRIMARY KEY(nro_sala, id_funcion)`.
- `COMPONE`: `UNIQUE(cod_espacio_publicitario, cod_publicidad)`.
- `COMPRA_EN`: `PRIMARY KEY(id_kiosko, id_cliente)` según el alcance definido.
- `ADMINISTRA_LA`: `PRIMARY KEY(id_empleado, id_funcion)`.
- `COMPRA_LA`: `UNIQUE(id_cliente, id_entrada)`.
- `LIMPIA_LA`: `PRIMARY KEY(id_empleado, nro_sala)`.

No declarar `UNIQUE(codigo_pelicula, codigo_cartelera)` en `FUNCION`, porque una película puede aparecer varias veces en la misma cartelera.

## Paso 1.4 - Revisar tipos de datos

Priorizar tipos que expresen correctamente el dominio:

- Duraciones: `integer` en minutos o `interval`, pero usar una estrategia única.
- Inicio y fin de función: `timestamptz` si se modela una fecha y hora completas.
- Precio: `numeric(10,2)` en lugar de `float`.
- Fechas de cartelera: `date` o `daterange` según el diseño final.
- Clasificaciones, tipos y métodos: `ENUM` o tablas catálogo documentadas.
- Correos: mantener el dominio `email`, pero documentar sus limitaciones.

El cambio de `TIME` a una representación con fecha y zona horaria es importante: una hora sola no alcanza para aplicar correctamente la regla de no solapamiento entre días.

---

# Fase 2 - Formalizar cartelera, horario y función

## Paso 2.1 - Incorporar la sucursal a la cartelera

La descripción indica que cada sucursal tiene su propia cartelera. Por eso `CARTELERA` debe referenciar a `SUCURSAL`.

La cartelera debería tener como mínimo:

```text
id_cartelera
id_sucursal
fecha_inicio
fecha_fin
```

Agregar una restricción para que una sucursal no tenga dos carteleras activas para el mismo período.

## Paso 2.2 - Definir el período de cartelera

La cartelera se actualiza semanalmente los jueves. Hay dos alternativas válidas:

- Guardar `fecha_inicio` y `fecha_fin`.
- Guardar un rango `daterange`.

La segunda opción permite una restricción `EXCLUDE` para evitar períodos superpuestos por sucursal.

## Paso 2.3 - Revisar la tabla `HORARIO`

El modelo actual separa `HORARIO` de `FUNCION`. Antes de conservarlo, decidir si representa:

- un horario concreto de una función; o
- una plantilla reutilizable de horas.

Para este caso se recomienda que la función tenga una programación concreta y trazable. La solución más directa es que la programación incluya:

```text
fecha o fecha derivada de la cartelera
hora_inicio
hora_fin
```

Si se conserva `HORARIO`, debe quedar documentado que `FUNCION.id_horario` determina inequívocamente el intervalo de la función.

## Paso 2.4 - Definir la duración final

La duración final debe calcularse como:

```text
hora_fin = hora_inicio + duracion_pelicula + duracion_espacio_publicitario
```

El valor no debe ser escrito manualmente por la aplicación. Una función `BEFORE INSERT OR UPDATE` debe recalcularlo cuando cambien la película, el horario o el espacio publicitario.

## Paso 2.5 - Validar la identidad de una función

`FUNCION` debe mantener su PK `id_funcion`.

No se debe asumir que `codigo_pelicula + codigo_cartelera` identifica una función, porque puede haber varias funciones de la misma película en la cartelera.

La diferencia entre funciones puede surgir por:

- horario;
- idioma;
- tipo de proyección;
- espacio publicitario;
- programación específica.

---

# Fase 3 - Implementar integridad de salas y funciones

## Paso 3.1 - Validar la misma sucursal

Una función de una cartelera solo puede proyectarse en salas de la sucursal propietaria de esa cartelera.

Esta regla no queda garantizada por las FK actuales si `PROYECTA` referencia solo a `SALA` y `FUNCION` por separado. Se debe implementar mediante una de estas opciones:

1. Claves compuestas que incluyan la sucursal.
2. Una tabla de asignación con trigger de validación.
3. Una función de inserción controlada que realice la operación dentro de una transacción.

La opción elegida debe documentarse en `docs/decisiones-tecnicas.md`.

## Paso 3.2 - Validar compatibilidad 2D y 3D

Reglas:

- Una película o función 2D puede proyectarse en una sala 2D o 3D, según la política adoptada.
- Una función 3D solo puede proyectarse en una sala compatible con 3D.
- Una sala no puede recibir una función incompatible con su capacidad.

Implementar la regla con un trigger `BEFORE INSERT OR UPDATE` sobre la asignación `PROYECTA`, porque depende de datos de dos tablas.

## Paso 3.3 - Impedir solapamiento en una misma sala

La restricción crítica es:

```text
misma sala + misma fecha + intervalos superpuestos = operación rechazada
```

La solución preferida es una tabla de asignaciones que contenga o exponga el intervalo completo de la función y una restricción:

```sql
EXCLUDE USING gist (
    nro_sala WITH =,
    tstzrange(inicio, fin, '[)') WITH &&
)
```

El rango `[)` permite que una función termine exactamente cuando comienza la siguiente.

Ejemplo válido:

```text
14:00 - 15:30
15:30 - 17:00
```

Ejemplo inválido:

```text
14:00 - 15:30
15:00 - 16:30
```

Antes de usar `EXCLUDE`, habilitar `btree_gist` y verificar que el modelo tenga una fecha completa, no solo `TIME`.

## Paso 3.4 - Validar cantidad de funciones de una cartelera

La regla de negocio debe interpretarse con cuidado. Si significa “no superar la capacidad operativa de salas”, no basta con contar funciones globales, porque una misma función puede estar en varias salas.

Documentar la interpretación elegida:

- cantidad de asignaciones a salas; o
- cantidad de funciones activas simultáneamente; o
- capacidad máxima de programación de la sucursal.

No implementar esta regla hasta fijar esa interpretación en la documentación.

## Paso 3.5 - Garantizar al menos una función

La regla “cada cartelera debe tener al menos una función” no puede expresarse con un `CHECK` sobre `CARTELERA`, porque depende de filas hijas.

Implementarla mediante:

- validación al cerrar o publicar la cartelera; o
- procedimiento transaccional `publicar_cartelera()` que verifique la condición antes de cambiar el estado.

Esto evita impedir la creación temporal de una cartelera durante una carga por etapas.

---

# Fase 4 - Implementar publicidad y clasificación

## Paso 4.1 - Mantener la relación `COMPONE`

`COMPONE` representa correctamente que un espacio publicitario contiene varias publicidades y que una publicidad puede reutilizarse en varios espacios.

La clave alternativa debe ser:

```text
(cod_espacio_publicitario, cod_publicidad)
```

## Paso 4.2 - Validar contenido mínimo

La política indica que un espacio debe tener al menos:

- un trailer;
- una publicidad de negocio;
- una promoción de sucursal.

Esta regla debe aplicarse al publicar o activar el espacio, no necesariamente durante cada inserción parcial.

Crear una función de validación que cuente los tipos requeridos.

## Paso 4.3 - Calcular duración

La duración del espacio debe ser la suma de las duraciones de sus publicidades.

La función debe recalcular el total cuando se inserte, modifique o elimine una fila de `COMPONE`. El trigger actual cubre principalmente inserciones y actualizaciones; debe contemplar también eliminaciones.

## Paso 4.4 - Calcular clasificación máxima

La clasificación del espacio debe ser la más restrictiva de sus publicidades:

```text
ATP < P-13 < P-16 < P-18
```

Se recomienda evitar depender del orden textual del `ENUM`. Crear una tabla catálogo con una prioridad numérica o una función explícita de prioridad.

## Paso 4.5 - Comparar publicidad y película

La clasificación del espacio publicitario debe ser compatible con la clasificación de la película proyectada.

Esta validación debe ejecutarse cuando:

- se asigna un espacio a una función;
- se cambia la película de una función;
- se modifica el contenido del espacio publicitario;
- cambia la clasificación de una publicidad.

---

# Fase 5 - Implementar entradas y asientos

## Paso 5.1 - Corregir la identificación de la sala

Como una función puede proyectarse en varias salas, `ENTRADA` no debe referenciar únicamente `id_funcion` para determinar el asiento.

Debe referenciar una asignación concreta de función y sala, por ejemplo:

```text
funcion_sala_id
nro_asiento
```

O bien utilizar una FK compuesta hacia:

```text
PROYECTA(nro_sala, id_funcion)
```

## Paso 5.2 - Validar el número de asiento

La entrada debe rechazar:

```text
nro_asiento < 1
nro_asiento > cantidad_de_asientos_de_la_sala
```

El trigger actual debe modificarse para resolver de forma inequívoca la sala asignada, sin buscar una única sala para una función que puede tener varias.

## Paso 5.3 - Impedir doble venta

La regla debe quedar declarada como unicidad:

```text
UNIQUE(funcion_sala_id, nro_asiento)
```

Esto protege la venta incluso ante dos transacciones simultáneas que intenten ocupar el mismo asiento.

El código de la aplicación debe capturar el error de restricción y mostrar que el asiento ya fue ocupado.

## Paso 5.4 - Registrar la compra

`ENTRADA` debe registrar como mínimo:

- función o asignación función-sala;
- número de asiento;
- método de compra;
- fecha y hora de compra.

Los datos derivados de la película, sala y horario no deberían duplicarse salvo que exista una decisión explícita de conservar una fotografía histórica de la venta.

## Paso 5.5 - Validar edad cuando corresponda

Si el dominio exige DNI para funciones con clasificación superior a ATP, esa regla debe implementarse en una función transaccional de venta, porque depende de:

- clasificación de la película;
- método de compra;
- identidad del cliente.

---

# Fase 6 - Revisar empleados, kiosko y proveedores

Estas entidades forman parte del dominio completo, aunque no son el foco principal del caso.

## Paso 6.1 - Gerente único por sucursal

La descripción establece un solo gerente por sucursal. El esquema actual almacena el rol del empleado, pero necesita una regla que impida dos gerentes activos en la misma sucursal.

Usar un índice único parcial o una validación equivalente:

```sql
UNIQUE (id_sucursal) WHERE empleado = 'gerente'
```

## Paso 6.2 - Empleados de limpieza

Una persona de limpieza debe estar asociada al menos a una sala. La condición de existencia de al menos una relación `LIMPIA_LA` debe validarse al activar o cerrar la asignación del empleado.

## Paso 6.3 - Personal de atención en kiosko

La descripción indica que trabajan en grupos de dos o más. La regla depende del contexto de cada kiosko y turno, por lo que el modelo actual `TRABAJA_EN` debería revisarse si se quiere demostrar esa regla.

Una evolución posible es agregar una entidad de turno:

```text
turno_kiosko
    id_turno
    id_kiosko
    inicio
    fin

trabaja_en
    id_empleado
    id_turno
```

Si esta ampliación queda fuera del alcance, documentar que la regla no se implementa en esta versión.

## Paso 6.4 - Un kiosko por sucursal

Agregar unicidad sobre `kiosko.id_sucursal`, porque el universo establece que cada sucursal posee un solo kiosko.

## Paso 6.5 - Stock

El universo menciona stock, pero el esquema original debe comprobar si existe una entidad específica para cantidad disponible. Si no existe, agregarla:

```text
stock_kiosko(id_kiosko, id_articulo, cantidad)
```

La relación `VENDE` indica qué artículos comercializa un kiosko, pero no reemplaza el stock.

---

# Fase 7 - Reescribir las funciones y triggers

Cada función y trigger debe tener una responsabilidad única y una regla documentada.

## Funciones recomendadas

- `fn_calcular_hora_fin()`
- `fn_validar_asignacion_sala()`
- `fn_validar_compatibilidad_sala()`
- `fn_validar_asiento()`
- `fn_validar_publicidad_minima()`
- `fn_calcular_duracion_espacio()`
- `fn_calcular_clasificacion_espacio()`
- `fn_validar_clasificacion_publicidad()`
- `fn_validar_cartelera_publicable()`

## Convenciones

Todas las funciones deben:

- usar `LANGUAGE plpgsql` cuando corresponda;
- declarar `SECURITY INVOKER` explícitamente;
- usar `CREATE OR REPLACE FUNCTION`;
- emitir errores legibles;
- usar `ERRCODE` cuando la operación viole una regla de integridad;
- incluir `HINT` si ayuda a corregir la operación;
- evitar consultas ambiguas que puedan devolver varias filas;
- documentar qué regla protegen.

Ejemplo de error profesional:

```sql
RAISE EXCEPTION USING
    ERRCODE = '23P01',
    MESSAGE = 'La sala ya tiene una funcion superpuesta en ese horario',
    HINT = 'Seleccione otra sala u otro horario';
```

---

# Fase 8 - Crear datos de seed consistentes

## Paso 8.1 - Separar catálogo y escenario

El seed debe cargarse en este orden:

1. sucursales;
2. empleados;
3. salas;
4. kioskos;
5. proveedores y artículos;
6. clientes;
7. películas;
8. publicidades;
9. espacios publicitarios;
10. carteleras;
11. horarios y funciones;
12. asignaciones `PROYECTA`;
13. relaciones `COMPONE`;
14. entradas y compras;
15. relaciones operativas restantes.

## Paso 8.2 - Evitar IDs asumidos

El seed actual utiliza varios IDs numéricos directamente. Reemplazar esas referencias por búsquedas estables o variables controladas.

No depender de que una identidad siempre empiece en 1.

## Paso 8.3 - Crear datos que demuestren las reglas

El escenario debe incluir:

- dos funciones simultáneas en salas diferentes;
- una función proyectada en dos salas;
- funciones consecutivas sin solapamiento;
- una operación inválida por solapamiento;
- una película 3D en sala compatible;
- una asignación 3D en sala incompatible;
- venta válida de un asiento;
- intento de doble venta del mismo asiento;
- espacio publicitario con clasificación compatible;
- espacio publicitario incompatible con la película.

---

# Fase 9 - Diseñar la batería de pruebas

## Paso 9.1 - Casos positivos

`tests/casos-positivos.sql` debe demostrar que pasan:

- varias funciones a la misma hora en salas distintas;
- la misma función en varias salas;
- funciones consecutivas en una misma sala;
- entradas para distintos asientos;
- publicidad reutilizada en distintos espacios;
- actualización automática de hora final;
- cálculo de duración y clasificación del espacio.

## Paso 9.2 - Casos negativos

`tests/casos-negativos.sql` debe demostrar que se rechazan:

- funciones superpuestas en la misma sala;
- funciones asignadas a salas de otra sucursal;
- proyección 3D en una sala incompatible;
- asiento fuera del rango de la sala;
- doble venta del mismo asiento;
- cartelera sin funciones al publicarse;
- espacio publicitario sin los tipos requeridos;
- publicidad incompatible con la clasificación de la película;
- segundo gerente activo en una sucursal;
- eliminación de entidades protegidas por entradas o dependencias.

Los casos negativos deben verificar el código SQLSTATE esperado, no solo que “ocurrió algún error”.

## Paso 9.3 - Pruebas de concurrencia

Crear dos sesiones que intenten vender simultáneamente el mismo asiento.

Resultado esperado:

- una transacción confirma la venta;
- la otra espera o falla por la restricción de unicidad;
- nunca quedan dos entradas para el mismo asiento;
- la consistencia no depende de una consulta previa de disponibilidad.

Crear también una prueba de dos transacciones que intenten asignar funciones superpuestas a la misma sala. La restricción temporal debe resolver la carrera en el motor.

---

# Fase 10 - Automatización local

## Paso 10.1 - Docker Compose

Configurar PostgreSQL 16 con:

- volumen persistente opcional para desarrollo;
- variables de entorno documentadas;
- healthcheck;
- puerto configurable;
- base y usuario de laboratorio.

No incluir credenciales reales.

## Paso 10.2 - Makefile

Targets mínimos:

```text
make up
make down
make reset
make test
make test-negative
make test-concurrency
make psql
```

## Paso 10.3 - Script de reset

`scripts/reset-db.sh` debe:

1. detener o limpiar el esquema de forma controlada;
2. ejecutar `99-drop.sql` si corresponde;
3. aplicar `01-schema.sql`;
4. aplicar `02-functions.sql`;
5. aplicar `03-triggers.sql`;
6. aplicar `04-seed.sql`;
7. abortar ante cualquier error.

Usar `psql --set ON_ERROR_STOP=1`.

## Paso 10.4 - Script de pruebas

`scripts/run-tests.sh` debe ejecutar las pruebas positivas, negativas y de concurrencia, y devolver código distinto de cero ante un fallo.

---

# Fase 11 - Documentación técnica

## `docs/modelo-conceptual.md`

Explicar:

- sucursal, sala y cartelera;
- película, horario y función;
- relación `PROYECTA`;
- entradas y asientos;
- publicidad y espacios publicitarios;
- kiosko, artículos y proveedores;
- empleados y roles.

## `docs/reglas-de-negocio.md`

Crear una matriz con esta estructura:

| ID | Regla | Objeto SQL | Tipo de protección | Prueba |
|---|---|---|---|---|
| R-01 | No solapamiento por sala | `EXCLUDE` | Declarativa | `NEG-01` |
| R-02 | Asiento único por función-sala | `UNIQUE` | Declarativa | `NEG-02` |
| R-03 | Hora final automática | Trigger | Procedural | `POS-03` |
| R-04 | Sala compatible con 3D | Trigger | Procedural | `NEG-03` |
| R-05 | Clasificación publicitaria compatible | Trigger | Procedural | `NEG-04` |

## `docs/decisiones-tecnicas.md`

Documentar al menos:

1. Por qué se conserva `PROYECTA` como relación N:M.
2. Por qué no se usa `UNIQUE(cartelera, hora_inicio)`.
3. Por qué se usa `EXCLUDE USING gist` para el solapamiento.
4. Qué reglas se resuelven con constraints y cuáles con triggers.
5. Cómo se garantiza la venta concurrente de asientos.

## `README.md`

El README final debe incluir:

- problema del dominio;
- arquitectura de datos;
- DER;
- reglas críticas;
- instrucciones de ejecución;
- ejemplo de prueba positiva;
- ejemplo de prueba rechazada;
- explicación de concurrencia;
- límites conocidos del caso.

No presentar el origen como “trabajo práctico”. Presentarlo como la evolución documentada de un modelo relacional hacia un laboratorio de integridad transaccional.

---

# Fase 12 - Diagrama y presentación

## Paso 12.1 - Migrar Draw.io a PlantUML

Usar `modelo conceptual.drawio` como fuente de comprensión, no necesariamente como entregable único.

Crear `diagrama/der.puml` con:

- entidades principales;
- PK y FK;
- cardinalidades;
- tablas asociativas;
- separación visual entre programación, ventas, publicidad y operación.

## Paso 12.2 - Agregar diagrama de reglas

Crear `diagrama/flujo-reglas.puml` con el flujo:

```text
Crear funcion
    -> asignar cartelera
    -> calcular intervalo
    -> asignar sala
    -> validar sucursal y formato
    -> validar no solapamiento
    -> habilitar venta
    -> validar asiento y concurrencia
```

## Paso 12.3 - Exportar el DER

Generar `der.png` desde PlantUML y embeberlo en el README.

---

# Orden de implementación recomendado

Este es el orden práctico para desarrollar el caso sin abrir demasiados frentes simultáneamente:

1. Copiar el DDL original a `sql/01-schema.sql`.
2. Uniformar nombres sin cambiar todavía la lógica.
3. Corregir claves candidatas y tipos monetarios.
4. Agregar sucursal y período a `CARTELERA`.
5. Resolver la representación de fecha, inicio y fin de función.
6. Separar funciones, triggers y seed.
7. Corregir la asignación de entradas a una sala concreta.
8. Implementar cálculo de hora final.
9. Implementar validación de sala y sucursal.
10. Implementar no solapamiento temporal.
11. Implementar unicidad de asiento vendido.
12. Implementar reglas de publicidad.
13. Implementar reglas mínimas de empleados y kiosko.
14. Reescribir el seed con referencias estables.
15. Crear pruebas positivas.
16. Crear pruebas negativas con SQLSTATE esperado.
17. Crear pruebas de concurrencia.
18. Automatizar Docker, Makefile y scripts.
19. Migrar el diagrama a PlantUML.
20. Redactar README, matriz de reglas y decisiones técnicas.
21. Ejecutar una verificación limpia desde cero.
22. Publicar el repositorio como caso de portafolio.

---

# Criterio de finalización

El Caso 3 está listo cuando una persona externa puede:

1. clonar el repositorio;
2. levantar PostgreSQL con Docker;
3. ejecutar un comando de reset;
4. cargar el esquema y los datos sintéticos;
5. correr las pruebas;
6. observar que las operaciones válidas pasan;
7. observar que las operaciones inválidas son rechazadas;
8. verificar que una carrera de venta no duplica asientos;
9. leer el DER y entender las relaciones;
10. identificar qué regla protege cada constraint, función o trigger.

La señal principal de calidad no será la cantidad de tablas, sino la trazabilidad:

```text
Regla de negocio
    -> decisión de modelado
    -> objeto SQL
    -> prueba reproducible
```

Ese será el eje profesional del repositorio `postgresql-business-rules`.
