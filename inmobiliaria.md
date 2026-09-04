# Modelo Entidad-Relación — Sistema Inmobiliaria

## 1. Entidades y atributos

| Entidad | Atributos clave | Notas |
|---|---|---|
| `propietario` | id_propietario (PK), nombre, documento (UNIQUE), telefono, correo, direccion | Dueño del inmueble consignado a la inmobiliaria |
| `cliente` | id_cliente (PK), nombre, documento (UNIQUE), telefono, correo, direccion | Puede ser comprador o arrendatario, sin distinguir tipo (así se solicitó) |
| `agente` | id_agente (PK), nombre, documento (UNIQUE), telefono, correo, fecha_contratacion, usuario_mysql | Empleado de la inmobiliaria, mapeado 1 a 1 a un usuario de MySQL |
| `tipo_propiedad` | id_tipo_propiedad (PK), nombre_tipo (UNIQUE: casa/apartamento/local_comercial), porcentaje_comision | Catálogo. La comisión depende del **tipo**, no del agente ni de la propiedad individual |
| `estado_propiedad` | id_estado (PK), nombre_estado (UNIQUE: disponible/reservada/arrendada/vendida/en_mantenimiento) | Catálogo, permite auditar cambios por id en vez de strings |
| `propiedad` | id_propiedad (PK), direccion, area, precio, modalidad (venta/arriendo), id_tipo_propiedad (FK), id_estado (FK), id_propietario (FK), fecha_registro | Todos los tipos comparten los mismos atributos, según se definió |
| `contrato` | id_contrato (PK), id_propiedad (FK), id_cliente (FK), id_agente (FK), tipo_contrato (venta/arriendo), fecha_inicio, fecha_fin, valor, deposito, dia_pago, estado_contrato | Tabla única para ambos tipos de contrato |
| `pago` | id_pago (PK), id_contrato (FK), fecha_esperada, fecha_pago, monto, mora, metodo_pago, estado_pago | Aplica a ventas (1 pago) y arriendos (n pagos mensuales) |
| `auditoria_propiedad` | id_auditoria (PK), id_propiedad (FK), estado_anterior, estado_nuevo, fecha_cambio, usuario_mysql | Poblada por trigger |
| `auditoria_contrato` | id_auditoria (PK), id_contrato (FK), accion, fecha_registro, usuario_mysql, detalle | Poblada por trigger |
| `reporte_pagos_pendientes` | id_reporte (PK), fecha_generacion, id_contrato (FK), id_cliente, id_propiedad, monto_pendiente | Poblada por el evento programado mensual |

## 2. Relaciones (cardinalidad)

- `propietario (1) — (N) propiedad`: un propietario puede consignar varias propiedades.
- `tipo_propiedad (1) — (N) propiedad`, `estado_propiedad (1) — (N) propiedad`.
- `propiedad (1) — (N) contrato`: una propiedad puede tener varios contratos a lo largo del tiempo (uno activo a la vez, controlado por lógica de aplicación/trigger).
- `cliente (1) — (N) contrato`, `agente (1) — (N) contrato`.
- `contrato (1) — (N) pago`.
- `propiedad (1) — (N) auditoria_propiedad`, `contrato (1) — (N) auditoria_contrato`.
- `contrato (1) — (N) reporte_pagos_pendientes` (histórico mes a mes).

## 3. Justificación de normalización (hasta 3FN)

- **1FN**: todos los atributos son atómicos (ej. no se guardan "telefono1, telefono2"; no se guardan listas en una sola celda).
- **2FN**: no hay tablas con clave compuesta que tengan atributos dependientes de solo una parte de la clave (todas las PK son simples, autoincrementales).
- **3FN**: se eliminaron dependencias transitivas:
  - `tipo_propiedad` se separó de `propiedad` porque `porcentaje_comision` depende del **tipo**, no de la propiedad en sí (si estuviera en `propiedad`, cambiar la comisión de "apartamento" obligaría a actualizar N filas y generaría inconsistencias).
  - `estado_propiedad` se separó por la misma razón y para permitir auditar el histórico de estados sin depender de un ENUM embebido.
  - Los datos de `cliente`, `agente` y `propietario` no se repiten dentro de `contrato`/`propiedad`; solo se referencian por FK.
  - `pago` no repite datos de `contrato` (valor, cliente, propiedad); se accede vía JOIN.

## 4. Decisiones de diseño explícitas (confirmadas contigo)

1. Las tres clases de propiedad comparten el mismo conjunto de atributos → **una sola tabla `propiedad`**, diferenciada por `id_tipo_propiedad`.
2. Una propiedad tiene una sola modalidad (venta **o** arriendo), campo `modalidad` en `propiedad`.
3. `cliente` es una sola tabla sin distinguir comprador/arrendatario (el rol se deduce del `tipo_contrato` en `contrato`).
4. La comisión del agente varía por **tipo de propiedad** y aplica tanto a venta como a arriendo → vive en `tipo_propiedad.porcentaje_comision`, y se calcula con la UDF `fn_calcular_comision`.
5. **Contrato único** con campo `tipo_contrato` (venta/arriendo) en vez de tablas separadas, tal como pediste; los campos que no aplican a un tipo (ej. `deposito`, `dia_pago`, `fecha_fin` en venta) quedan `NULL`.
6. `pago` aplica a ambos tipos de contrato: en venta se registra un único pago de contado; en arriendo se generan pagos mensuales.
7. La deuda pendiente en arriendo se calcula como: **Σ (monto + mora) de pagos con `fecha_esperada <= HOY` y `estado_pago <> 'pagado'`**.
8. Usuarios MySQL corresponden 1 a 1 con agentes/contador; el administrador es una cuenta separada.
9. **Supuesto que debes validar**: la comisión de arriendo se calcula sobre el canon mensual (`contrato.valor`), igual fórmula que en venta. Si tu criterio de evaluación espera otra base (ej. canon × número de meses), es un cambio de una línea en la función `fn_calcular_comision`.
10. **Trigger adicional agregado** (no pedido explícitamente pero necesario para la coherencia del sistema): al insertar un contrato, la propiedad cambia automáticamente su estado ("disponible" → "arrendada"/"vendida"), lo cual a su vez dispara el trigger de auditoría de `propiedad`.

## 5. Diagrama (notación textual simplificada)

```
propietario 1---N propiedad N---1 tipo_propiedad
                       |
                       N---1 estado_propiedad
                       |
                       1
                       N
cliente 1---N contrato N---1 agente
                       |
                       1
                       N
                     pago

propiedad ---auditoria_propiedad (trigger)
contrato  ---auditoria_contrato (trigger)
contrato  ---reporte_pagos_pendientes (evento mensual)
```
