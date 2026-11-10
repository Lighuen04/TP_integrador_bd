# Esquema relacional — Bodegas del Atuel

## Alcance

El esquema visual completo está en [modelo_relacional.dbml](./modelo_relacional.dbml). Se puede abrir y previsualizar con una extensión de VS Code compatible con DBML. Este archivo documenta las claves, referencias y decisiones de mapeo; **no** contiene sentencias `CREATE TABLE`, funciones, triggers, API ni frontend.

Fuentes consultadas: los archivos actuales `DER.drawio.xml` y `TPI_Bodegas_del_Atuel.md`. La página 2 del XML está vacía. La página 1 tiene 22 entidades, 25 relaciones y 97 óvalos de atributos. El detalle elemento por elemento está en [trazabilidad_der_relacional.md](./trazabilidad_der_relacional.md); las reglas RN-01 a RN-15 se contrastan en [validacion_tpi.md](./validacion_tpi.md).

## Relaciones y claves

| Módulo | Tabla(s) | Clave primaria | Relaciones principales |
|---|---|---|---|
| Geografía y personal | `localidad` | `codigo_postal` | Identificador marcado en el DER; se conserva como clave natural. Referenciada por clientes, salas, fincas y cobertura de transportistas. |
| Geografía y personal | `sala_venta` | `id_sala` | FK a localidad; referenciada por empleados, comprobantes, transferencias y stock. |
| Geografía y personal | `empleado` | `cuit` | FK obligatoria a sala. |
| Producción de uva | `finca` | `id_finca` | `codigo_postal` es FK NOT NULL a Localidad; una localidad puede tener varias fincas. La provincia se consulta desde Localidad y no se duplica en Finca. |
| Producción de uva | `parcela` | (`id_finca`, `numero_parcela`) | Entidad débil indicada gráficamente por doble contorno; FK a finca y a una cepa. |
| Producción de uva | `lote_uva` | `numero_lote` | Identificador marcado en el DER. Además, UNIQUE (`id_finca`, `numero_parcela`, `campania`) impone una cosecha como máximo por parcela/campaña. |
| Producción de uva | `analisis_calidad` | `id_analisis` | FK a `numero_lote`. |
| Bodegas, vinos y catálogos | `bodega` | `cuit` | Referenciada por lotes, vinos e ingresos. |
| Bodegas, vinos y catálogos | `vino` | `codigo_vino` | FK a bodega; relacionado con cepas, maridajes, comprobantes, ingresos, transferencias y stocks. |
| Bodegas, vinos y catálogos | `cepa` | `id_cepa` | Relacionada con parcelas y vinos. |
| Bodegas, vinos y catálogos | `composicion_vino_cepa` | (`codigo_vino`, `id_cepa`) | Asociación N:M; contiene `porcentaje_corte`. |
| Bodegas, vinos y catálogos | `maridaje` | `id_maridaje` | Catálogo de maridajes. |
| Bodegas, vinos y catálogos | `vino_maridaje` | (`codigo_vino`, `id_maridaje`) | Asociación N:M. |
| Clientes y ventas | `cliente` | `id_cliente` | Discriminador `tipo_cliente`; FK a localidad. |
| Clientes y ventas | `socio`, `distribuidor`, `exportador` | `id_cliente` en cada subtipo | Clave compartida PK/FK al supertipo. |
| Clientes y ventas | `permiso_exportacion` | `codigo_permiso` | FK a exportador. |
| Clientes y ventas | `comprobante` | `numero_comprobante` | FK a cliente y sala; conserva el porcentaje histórico aplicado y `total` como resumen agregado mantenido automáticamente. |
| Clientes y ventas | `comprobante_vino` | (`numero_comprobante`, `codigo_vino`) | Renglón del comprobante; cantidad y precio histórico; subtotal calculado. |
| Distribución y existencias | `transportista` | `codigo_transporte` | Relacionado con ingresos y localidades cubiertas. |
| Distribución y existencias | `transportista_localidad` | (`codigo_transporte`, `codigo_postal`) | Asociación N:M. |
| Distribución y existencias | `ingreso` | `codigo_ingreso` | FK a transportista y bodega. |
| Distribución y existencias | `ingreso_vino` | (`codigo_ingreso`, `codigo_vino`) | Renglón de ingreso; cantidad de botellas. |
| Distribución y existencias | `transferencia` | `numero_solicitud` | FK a sala solicitante. |
| Distribución y existencias | `transferencia_vino` | (`numero_solicitud`, `codigo_vino`) | Renglón de transferencia; cantidad de botellas. |
| Distribución y existencias | `stock_sala` | (`id_sala`, `codigo_vino`) | Stock por sala y vino; cantidad no negativa. |
| Distribución y existencias | `stock_deposito` | `codigo_vino` | PK/FK a vino; una fila de stock por vino en el depósito central. |
| Distribución y existencias | `auditoria_precios` | `id_auditoria` | FK a vino; precio anterior/nuevo, fecha, hora y usuario. |

## Transformación de relaciones

El esquema declara cuatro claves alternativas además de las claves primarias:
`lote_uva(id_finca, numero_parcela, campania)` por RN-04,
`vino(nombre_comercial, anada, presentacion_ml)` según el ejemplo explícito de
UNIQUE del TPI, `cliente(tipo_documento, numero_documento)` porque el documento
identifica al cliente dentro de su tipo, y `transportista(cuit)` porque el CUIT
identifica al contribuyente. `bodega.cuit` ya es clave primaria y no se cuenta
otra vez como restricción adicional.

- En las asociaciones 1:N la FK queda en el extremo N: por ejemplo, `sala_venta.codigo_postal`, `empleado.id_sala`, `comprobante.id_cliente`, `vino.cuit_bodega`, `ingreso.cuit_bodega` y `transferencia.id_sala`.
- Las asociaciones N:M se convierten en tablas con PK compuesta: composición, maridaje, renglones de comprobante, cobertura de transportistas, renglones de ingreso, renglones de transferencia y stock de sala.
- El stock central se representa como una fila por vino: la clave del registro es también FK a vino, según el requisito de stock central.
- La relación parcela-cepa se representa mediante FK en parcela porque el TPI establece una sola cepa por parcela.
- Localidad–Finca es 1:N: cada finca referencia exactamente una localidad y una localidad puede asociarse a varias fincas. Se implementa con `finca.codigo_postal` como FK NOT NULL y sin UNIQUE. La provincia se recupera mediante JOIN a Localidad.
- Las subclases de cliente comparten la PK del supertipo. El discriminador conserva el tipo; la totalidad y disyunción de la ISA se documentan, pero requieren validación entre filas que DBML no puede expresar por sí solo.

La relación Localidad–Finca queda fijada por decisión aprobada como 1:N, con participación obligatoria de Finca; prevalece esta decisión sobre la lectura anterior de rótulos gráficos. La columna `finca.provincia` se elimina: provincia se obtiene con JOIN por `codigo_postal` hacia `localidad`. Las cardinalidades y transformaciones restantes se detallan en la trazabilidad.

El descuento vigente se almacena en `cliente.descuento`: RN-06 establece valores base de 10 %, 20 % y 30 %, mientras que U6 exige una actualización a 35 % para exportadores con más de tres permisos. U6 impide justificar `tipo_cliente → descuento` como dependencia funcional universal del valor vigente. Al crear un comprobante se copia el valor de `cliente.descuento` a `comprobante.descuento_aplicado`; esa copia constituye el descuento histórico de la venta. Modificar el descuento vigente de un cliente no actualiza comprobantes anteriores.

En cada renglón se calcula `subtotal bruto = cantidad × precio`. Todos los renglones de un comprobante usan `comprobante.descuento_aplicado`, y el total se calcula como `SUM(cantidad × precio) × (1 - descuento_aplicado / 100)`. No se duplica la tasa en los detalles. `comprobante.total` se almacena como resumen del neto agregado y se recalcula transaccionalmente al insertar, modificar o eliminar renglones, siempre con la tasa histórica de la cabecera. El resumen es redundante entre relaciones, pero la agregación sobre múltiples renglones no es una DF de fila de la cabecera; la prueba formal de 3FN se realiza por relación y no se usa el trigger como argumento de normalización.

**Interpretación aprobada de U1:** recalcular todos los totales usando el descuento histórico almacenado en cada comprobante, sin cambiar `descuento_aplicado`. La diferencia potencial entre esta decisión y la frase literal del TPI se conserva expresamente en [validacion_tpi.md](./validacion_tpi.md).

## Tipos y restricciones físicas

Se usan tipos PostgreSQL compatibles y exactos para el dominio: `numeric` para dinero, superficies, kilogramos, porcentajes y medidas; `varchar(11)` para CUIT (conserva posibles ceros iniciales); `date`/`time` para fechas y horas; enteros para cantidades; y un `ENUM` conceptual para el estado de ingreso y transferencia. Las precisiones elegidas son una propuesta de implementación, ya que el DER no define longitudes ni escalas.

El DBML declara PK, FK, tipos y las cuatro claves alternativas, pero no pretende expresar por sí solo restricciones entre filas. La implementación física de dominio CUIT, CHECK, composición, estados, stocks, `comprobante.total`, procesamiento idempotente, ISA, descuentos y auditoría se encuentra en [`../database/`](../database/README.md). Las claves alternativas se justifican en la sección anterior y en [normalizacion.md](./normalizacion.md); el TPI menciona explícitamente como ejemplo la unicidad de nombre/añada/presentación de Vino.

La demostración individual de 1FN, 2FN y 3FN para las 29 relaciones, con esquemas, claves candidatas, atributos primos/no primos, DF y las dos descomposiciones sin pérdida, se encuentra en [normalizacion.md](./normalizacion.md).

### Acciones referenciales implementadas

- `RESTRICT` para referencias desde movimientos y comprobantes hacia vinos, bodegas y transportistas, conforme a RN-14.
- Ingreso y Transferencia usan `CASCADE` hacia sus renglones. Comprobante usa `RESTRICT`: no se borra mientras tenga renglones. Cada detalle se elimina individualmente y repone stock mediante el único trigger de movimiento; luego puede borrarse la cabecera vacía. Ingresos y transferencias solo se pueden borrar en confección; una vez terminados o procesados se conservan como historial.
- `RESTRICT` para claves de cliente, sala, localidad, vino, bodega y transportista cuando su eliminación rompería datos operativos o históricos.
- `CASCADE` desde un cliente a su fila de subtipo compartida, sin permitir que esa acción eluda las referencias a comprobantes.

Las acciones se declaran en `database/02_tablas.sql` y se verifican con las pruebas físicas de `database/`.

## Decisiones aplicadas y puntos del TPI

1. Localidad–Finca queda definida como 1:N por decisión aprobada: `finca.codigo_postal` es FK NOT NULL sin UNIQUE.
2. `Finca.provincia` se elimina por decisión aprobada; se obtiene mediante JOIN a `Localidad.provincia`.
3. Los óvalos `tinto` y `blanco` de Cepa se interpretan como valores permitidos de `tipo`, no como atributos booleanos distintos.
4. Se conserva `cliente.descuento` como valor vigente por cliente para permitir U6; cada comprobante conserva una sola tasa histórica en `comprobante.descuento_aplicado`.
5. `comprobante.total` se persiste y se mantiene automáticamente. Esto introduce redundancia agregada entre cabecera y renglones; el trigger asegura consistencia operativa, no demuestra 3FN. U1 se interpreta según la decisión aprobada: recalcular desde el descuento histórico de cada comprobante.
6. Se preservan `codigo_postal` como PK de Localidad, `numero_lote` como PK de Lote y `(id_finca, numero_parcela)` como PK débil de Parcela. `ID_auditoria` continúa siendo una propuesta de clave técnica porque el óvalo está huérfano.
7. El TPI da como ejemplo una unicidad de nombre/año/presentación en vino. No se aplica en el DBML hasta confirmar que esa combinación es regla del dominio; `codigo_vino` es la clave identificadora.
8. La obligatoriedad de las FK se toma del escenario del TPI cuando expresa “una sola”, “cada”, “debe” o un dato necesario para un movimiento. El DER no expresa participación mínima.
