# Bitácora de Migración y Auditoría del Modelo Relacional

Este documento registra el inventario del material de origen, el diagnóstico técnico detallado de sus limitaciones y la matriz de transformación hacia el modelo final de ingeniería en PostgreSQL.

---

## 1. Inventario de Artefactos de Origen

| Artefacto Original | Contenido Principal | Tratamiento en la Migración |
|---|---|---|
| `sql ddl` | Definición de tipos ENUM, dominios regex, tablas, PK/FK y 5 triggers. | Se refactoriza y descompone en `sql/01-schema.sql`, `sql/02-functions.sql` y `sql/03-triggers.sql`. |
| `sql insert` | Inserciones de prueba con IDs numéricos asumidos y parches de actualización (`UPDATE funcion`). | Se reemplaza por `sql/04-seed.sql` estructurado, trazable y con relaciones consistentes. |
| `sql consultas` | 4 consultas de ejemplo del modelo original. | Se integran como vistas operativas en `sql/05-views.sql` (`v_programacion`, `v_publicidad_por_funcion`, `v_gerente_por_sucursal`, `v_limpieza_por_sala`), verificadas por la prueba P-17. La consulta de sucursales por película usaba la tabla `proyecta`, que ya no existe; ahora es `SELECT DISTINCT sucursal FROM v_programacion WHERE pelicula = ...`. |
| `modelo conceptual.drawio` | Diagramas conceptual y lógico de 2 páginas en formato Draw.io. | Se traduce a código fuente declarativo PlantUML (`diagramas/der.puml`) y se compila a imagen (`diagramas/der.png`). |
| `backup` | Respaldo binario en formato personalizado de PostgreSQL 16.4 (`pg_dump -Fc`). | Se conserva como archivo de solo lectura de respaldo histórico. |
| `Trabajo Practico Integrador - grupo  9.pdf` | Especificación del Universo del Discurso y decisiones de modelado iniciales. | Se utiliza como insumo de reglas de negocio y se retira antes del release público (sanitización de marcas académicas). |

---

## 2. Auditoría Técnica de Limitaciones y Soluciones

### A. Venta de Entradas y Prevención de Overbooking
- **Estado original:**  
  `entrada (codigo, id_funcion, nro_asiento, tipo_entrada, UNIQUE(nro_asiento, id_funcion))`  
  En el modelo de negocio, una misma función puede exhibirse en más de una sala simultáneamente (`proyecta (nro_sala, id_funcion)`).  
  Al no almacenar la sala en `entrada`:
  1. No era posible vender el asiento 1 en la Sala A y el asiento 1 en la Sala B para la misma función.
  2. El trigger `validar_numero_asiento()` realizaba un `SELECT ... WHERE proyecta.id_funcion = NEW.id_funcion`, arrojando el error `more than one row returned by a subquery used as an expression` si la función estaba asignada a más de una sala.
- **Solución implementada:**  
  Asociar la entrada a la tupla física de proyección mediante clave foránea compuesta:  
  `FOREIGN KEY (nro_sala, id_funcion) REFERENCES proyeccion(nro_sala, id_funcion)`  
  con restricción declarativa estricta:  
  `UNIQUE (nro_sala, id_funcion, nro_asiento)`.

### B. Control de Solapamiento Físico en Salas (Exclusión GiST)
- **Estado original:**  
  Entidad `horario` con `hora_inicio TIME` y `hora_fin TIME`.  
  El tipo `TIME` no contiene fecha ni zona horaria. Esto imposibilita validar superposiciones reales entre fechas distintas o funciones que culminan pasada la medianoche, y descarta el uso de tipos de rango nativos de PostgreSQL.
- **Solución implementada:**  
  - Habilitar la extensión `btree_gist`.
  - Representar la programación con marcas temporales completas (`timestamptz`).
  - Modelar la asignación física de sala con rangos de marcas de tiempo semiabiertos `[)`:
    ```sql
    CONSTRAINT proyeccion_sin_solapamiento EXCLUDE USING gist (
        nro_sala WITH =,
        rango_ocupacion WITH &&
    );
    ```

### C. Resolución del Ciclo de Dependencia Circular
- **Estado original:**  
  Trigger `trigger_verificar_funciones_en_cartelera` sobre `horario` que abortaba si no existía previamente una función en la cartelera. A su vez, `funcion` tenía una FK obligatoria a `horario`.  
  Esto requirió forzar `id_horario NULL` en `funcion` y parchar los registros con sentencias `UPDATE` posteriores.
- **Solución implementada:**  
  Se elimina la entidad `horario`: el horario pasa a ser un atributo de `funcion` (`fecha_hora_inicio`, con el fin calculado por trigger). La verificación que antes bloqueaba la carga se traslada al momento de publicar, con la función `fn_validar_cartelera_publicable(codigo_cartelera)`. Esta exige que la cartelera tenga funciones y que todas tengan sala asignada, lo que permite cargar la cartelera, sus funciones y sus proyecciones en cualquier orden.

### D. Recálculo Reactivo de Espacios Publicitarios
- **Estado original:**  
  Triggers `AFTER INSERT OR UPDATE ON compone` para recalcular duración acumulada y clasificación restrictiva. Ignoraba bajas de publicidades (`DELETE`).
- **Solución implementada:**  
  Extender el trigger para contemplar eventos `AFTER INSERT OR UPDATE OR DELETE ON compone`, garantizando que si se desvincula un trailer o anuncio, la duración y la clasificación máxima del espacio publicitario se recalculen fielmente.

### E. Normalización y Coherencia de Tipos de Datos
- **Precios monetarios:** De `float` a `numeric(10,2)` para prevenir pérdidas de precisión por redondeo binario.
- **Duraciones:** De `TIME` a enteros: minutos para películas y funciones (`duracion_min`, `duracion_total_min`) y segundos para las piezas publicitarias (`duracion_seg`).
- **Relación sucursal-cartelera:** Incorporación de `id_sucursal` en `cartelera`, asegurando que cada programación semanal pertenezca formalmente a su sede correspondiente, con vigencias que no se solapan por sucursal (`EXCLUDE USING gist` sobre `daterange`).
- **Gerencia única por sucursal:** Creación de un índice único parcial:  
  `CREATE UNIQUE INDEX empleado_gerente_por_sucursal_uidx ON empleado(id_sucursal) WHERE empleado = 'gerente';`

### F. Correcciones posteriores a la migración
La batería de pruebas detectó cuatro defectos en la primera versión migrada: propagación incompleta de horarios, espacios publicitarios en uso sin revalidar, atributos derivados editables y una secuencia identity desincronizada en el seed. Su análisis y corrección están en [`bugs-encontrados.md`](bugs-encontrados.md), y las decisiones de diseño que surgieron, en [`decisiones-tecnicas.md`](decisiones-tecnicas.md) (ADR-06, ADR-07 y ADR-08).

