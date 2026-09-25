# Reglas de negocio

Matriz de trazabilidad: qué regla protege cada objeto del motor, con qué error se rechaza una violación y qué pruebas lo verifican.

- **Pruebas:** `P-xx` en `tests/01-casos-positivos.sql`, `N-xx` en `tests/02-casos-negativos.sql`, `C-xx` en `tests/03-concurrencia.sql`.
- **SQLSTATE:** `23P01` exclusion_violation · `23505` unique_violation · `23503` foreign_key_violation · `23514` check_violation.
- Las reglas propias implementadas en PL/pgSQL usan los códigos estándar de integridad (`23514`, `23503`), así que el cliente las trata igual que una restricción declarativa. Como varias comparten `23514`, las pruebas también verifican un fragmento del mensaje para identificar la regla.

## Matriz

| ID | Regla | Mecanismo | Objeto SQL | Rechazo | Pruebas |
|---|---|---|---|---|---|
| **R-01** | Una sala física no puede alojar dos funciones solapadas en el tiempo, contando publicidad y limpieza. | Restricción de exclusión GiST sobre un rango semiabierto `[inicio, fin)` | `proyeccion_sin_solapamiento` · `trg_funcion_propagar_horario` · `trg_espacio_propagar_a_funciones` | `23P01` | P-04, P-06, P-07, P-09, P-10, P-11, P-14 · N-01…N-06 · C-03 |
| **R-02** | Un asiento no puede venderse dos veces para la misma proyección física. | Unicidad compuesta + FK compuesta a `proyeccion` | `entrada_asiento_unico` · `entrada_proyeccion_fk` | `23505` · `23503` | P-05 · N-07, N-10 · C-01, C-02 |
| **R-03** | El fin de una función se calcula: inicio + película + bloque publicitario (redondeado a minutos) + 20 min de limpieza. | Trigger `BEFORE INSERT OR UPDATE` | `fn_calcular_fin_funcion` · `trg_funcion_calcular_fin` | — (derivado) | P-02, P-11, P-12, P-14 |
| **R-04** | Una función 3D solo puede ir a salas 3D o IMAX, y una IMAX solo a salas IMAX. Una 2D puede ir a cualquier sala. | Trigger `BEFORE INSERT OR UPDATE` en `proyeccion` | `fn_validar_compatibilidad_sala` · `trg_proyeccion_validar_compatibilidad` | `23514` | P-08 · N-12, N-13, N-14 |
| **R-05** | El bloque publicitario no puede tener una clasificación etaria más restrictiva que la película. | Trigger en `funcion` + revalidación al cambiar el espacio | `fn_validar_clasificacion_espacio_pelicula` · `trg_funcion_validar_clasificacion` · `trg_espacio_propagar_a_funciones` | `23514` | N-15, N-16, N-17, N-18 |
| **R-06** | El número de asiento debe existir en la sala física (1 … capacidad). | Trigger + `CHECK` | `fn_validar_numero_asiento` · `trg_entrada_validar_asiento` · `entrada_nro_asiento_check` | `23514` | P-15 · N-08, N-09 |
| **R-07** | Una función solo puede proyectarse en salas de la sucursal dueña de su cartelera. | Trigger `BEFORE INSERT OR UPDATE` en `proyeccion` | `fn_validar_sucursal_proyeccion` · `trg_proyeccion_validar_sucursal` | `23503` | N-19 |
| **R-08** | Cada sucursal tiene como máximo un gerente. | Índice único parcial | `empleado_gerente_por_sucursal_uidx` | `23505` | P-17 · N-20 |
| **R-09** | La duración de un espacio publicitario es la suma de sus piezas. | Trigger `AFTER INSERT OR UPDATE OR DELETE` en `compone` | `fn_recalcular_espacio_publicitario` · `trg_compone_recalcular_espacio` | — (derivado) | P-03, P-13, P-14 |
| **R-10** | La clasificación de un espacio publicitario es la más restrictiva de sus piezas. | Mismo trigger que R-09 | `fn_recalcular_espacio_publicitario` | — (derivado) | P-03, P-13 · N-17 |
| **R-11** | Cada sucursal tiene como máximo un kiosko. | Unicidad | `kiosko_id_sucursal_key` | `23505` | N-21 |
| **R-12** | Una sucursal no puede tener carteleras con vigencias solapadas, y el fin de una vigencia no puede ser anterior a su inicio. | Exclusión GiST sobre `daterange` + `CHECK` | `cartelera_sucursal_periodo_excl` · `cartelera_fechas_orden_ck` | `23P01` · `23514` | N-22, N-23 |
| **R-13** | Una cartelera es publicable solo si tiene funciones y todas tienen sala asignada. | Función de verificación invocada al publicar | `fn_validar_cartelera_publicable(integer)` | `23514` | P-16 · N-24, N-25 |
| **R-14** | Los atributos derivados (`fecha_hora_fin`, `duracion_total_min`, `rango_ocupacion`) no se pueden editar a mano. | Triggers que siempre recalculan e ignoran el valor enviado | `trg_funcion_calcular_fin` · `trg_proyeccion_sincronizar_rango` | — (se recalcula) | P-12 |
| **R-15** | Formatos y valores válidos: email, código EAN-13, precios no negativos. | Dominios + `CHECK` | dominios `email`, `ean13` · `entrada_precio_check` · `articulo.precio > 0` | `23514` | N-11, N-26, N-27 |
| **R-16** | No se pueden borrar salas ni películas con funciones programadas. | FK `ON DELETE RESTRICT` | `proyeccion_nro_sala_fkey` · `funcion_codigo_pelicula_fkey` | `23503` | N-28, N-29 |

## Detalle de las reglas críticas

### R-01 — No solapamiento en salas físicas
```sql
CONSTRAINT proyeccion_sin_solapamiento EXCLUDE USING gist (
    nro_sala WITH =,
    rango_ocupacion WITH &&
)
```
- El rango es **semiabierto** `[inicio, fin)`: una función puede empezar exactamente cuando termina la anterior (P-07), pero un minuto antes ya no (N-02).
- El rango usa `timestamptz`, así que una función que cruza la medianoche se valida igual que cualquier otra (P-09, N-03).
- `rango_ocupacion` no lo carga el cliente: se deriva de la función (R-14). Cualquier cambio que altere el horario se propaga en cadena hasta la restricción: nuevo inicio (N-04), nueva película (N-05) o una pieza publicitaria más larga (N-06). Ver `diagramas/flujo-reglas.png`.
- Bajo concurrencia, una segunda transacción que intenta un rango solapado queda **bloqueada** hasta que la primera confirma, y entonces se rechaza (C-03).

### R-02 — Prevención de overbooking
```sql
CONSTRAINT entrada_proyeccion_fk FOREIGN KEY (nro_sala, id_funcion)
    REFERENCES proyeccion(nro_sala, id_funcion),
CONSTRAINT entrada_asiento_unico UNIQUE (nro_sala, id_funcion, nro_asiento)
```
- La entrada pertenece a una **proyección física** (función + sala), no solo a la función. Así, una función que se exhibe en dos salas puede vender el asiento 1 en cada una (P-05).
- Dos ventas simultáneas del mismo asiento: la segunda espera a que la primera confirme y se rechaza con `23505` (C-01). Si la primera revierte, la segunda se completa (C-02). No hace falta ningún lock explícito en la aplicación.

### R-03 — Horario de fin calculado
```
duracion_total_min = pelicula.duracion_min
                   + CEIL(espacio_publicitario.duracion_seg / 60)
                   + 20                                    -- limpieza
fecha_hora_fin     = fecha_hora_inicio + duracion_total_min
```
Ejemplo del seed: Toy Story 5 (100 min) + espacio 1 (225 s → 4 min) + 20 = 124 min, de 14:00 a 16:04 (P-02).

## Vistas de consulta

No protegen reglas, pero ofrecen una lectura operativa del modelo (`sql/05-views.sql`, prueba P-17):

| Vista | Contenido |
|---|---|
| `v_programacion` | Una fila por proyección física, con entradas vendidas y porcentaje de ocupación. |
| `v_publicidad_por_funcion` | Piezas publicitarias que se proyectan antes de cada función. |
| `v_gerente_por_sucursal` | Gerente de cada sucursal (`NULL` si no tiene). |
| `v_limpieza_por_sala` | Personal de limpieza asignado a cada sala. |
