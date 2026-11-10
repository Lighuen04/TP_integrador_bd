# Validación del modelo relacional frente al TPI

## Alcance

Se compararon las reglas RN-01 a RN-15 y las entidades mínimas con los archivos actuales `DER.drawio.xml` y `TPI_Bodegas_del_Atuel.md`. La tabla resume el modelo lógico y su implementación física, ubicada en [`../database/`](../database/README.md). No se incluyen aquí scripts SQL, API ni frontend.

El diseño y las decisiones de tipos están documentados en [esquema_relacional.md](./esquema_relacional.md); la normalización, en [normalizacion.md](./normalizacion.md); la comparación de todos los elementos del XML, en [trazabilidad_der_relacional.md](./trazabilidad_der_relacional.md).

## Reglas RN-01 a RN-15

| Regla | Tablas involucradas | Integridad requerida | Compatibilidad con 3FN | Implementación física |
|---|---|---|---|---|
| RN-01 | `vino` | Precio positivo y un precio vigente por `codigo_vino`. | Sí; precio depende de la PK. | `CHECK(precio > 0)` y UNIQUE de nombre/añada/presentación. |
| RN-02 | `localidad`, `sala_venta` | FK NOT NULL de sala a Localidad; encargado regional se registra una sola vez por localidad. | Sí; no se duplica el encargado en Sala. | FK `NOT NULL`; encargado almacenado en Localidad. |
| RN-03 | `empleado`, `sala_venta` | Cada empleado referencia una sala. | Sí; FK no crea DF parcial en Empleado. | FK `NOT NULL`. |
| RN-04 | `parcela`, `lote_uva`, `cepa` | Parcela débil con PK `(id_finca, numero_parcela)` y una cepa; PK `numero_lote` más UNIQUE `(id_finca, numero_parcela, campania)`. | Sí; la clave candidata adicional de Lote está incluida en la prueba. | PK, FK, UNIQUE y CHECK de superficies/kilos positivos. |
| RN-05 | `composicion_vino_cepa` | Los porcentajes por vino deben sumar exactamente 100. | Sí; es una restricción agregada, no una DF parcial. | CHECK por porcentaje y constraint trigger diferido para suma exacta. |
| RN-06 | `cliente`, `socio`, `distribuidor`, `exportador`, `permiso_exportacion` | ISA total/disjunta; tasas base por tipo; U6 actualiza el descuento vigente de exportadores elegibles a 35 %. | Sí; `id_cliente → descuento`; no se supone `tipo_cliente → descuento` universal para el valor vigente. | Triggers diferidos ISA, inicialización de tasa y validación de elegibilidad de 35 %. |
| RN-07 | `permiso_exportacion` | Vencimiento posterior a emisión; varios permisos por exportador. | Sí; fechas dependen de la PK del permiso. | `CHECK` entre fechas y FK. |
| RN-08 | `comprobante`, `comprobante_vino`, `cliente` | Al crear el comprobante se copia `cliente.descuento` a `comprobante.descuento_aplicado`; todos sus renglones usan esa tasa histórica. `total = SUM(cantidad × precio) × (1 - descuento_aplicado / 100)`. Cambios posteriores del descuento vigente no alteran ventas previas. | Sí por DF de cada relación tras trasladar la DF parcial del descuento a Comprobante. `total` tiene redundancia agregada entre relaciones, no una DF de fila no-clave. | Trigger de cabecera inicializa el total y rechaza UPDATE cuyo importe difiera del cálculo histórico. El trigger de renglones recalcula transaccionalmente; U1 conserva la tasa histórica. |
| RN-09 | `stock_sala`, `comprobante_vino`, `vino` | Saldo sala-vino no negativo y venta no superior al stock. | Sí; saldo depende de PK compuesta; validación de suficiencia es transaccional. | CHECK, débito condicional atómico y permisos que prohíben al rol API editar el stock. |
| RN-10 | `ingreso`, `ingreso_vino`, `stock_deposito` | Solo ingreso terminado impacta el depósito y pasa a procesado una sola vez. | Sí; estados y saldos dependen de sus claves; idempotencia es regla operativa. | Trigger de transición y `sp_procesar_ingreso` dentro de una transacción. |
| RN-11 | `transferencia`, `transferencia_vino`, `stock_deposito`, `stock_sala` | Transferencia terminada descuenta depósito y acredita sala solo una vez; fecha se fija al crear; no procesar si falta stock. | Sí; restricciones de saldo y transición no son DF. | `sp_procesar_transferencia`, trigger, bloqueos y débitos/créditos atómicos. |
| RN-12 | `ingreso`, `ingreso_vino`, `transferencia`, `transferencia_vino` | Solo cabeceras en confección admiten DML directo de renglones; excepción documental D5 aprobada por el proyecto en B.2. | Sí; es regla de mutabilidad, no dependencia funcional. | Trigger verifica estado; solo la cascada de una cabecera ya eliminada permite quitar su detalle sin modificar stock. |
| RN-13 | `vino`, `auditoria_precios` | Todo cambio efectivo de precio guarda valor anterior/nuevo, fecha y usuario. | Sí; cada evento tiene PK propia; relación temporal no altera las DF de fila. | Trigger audita cambios efectivos y usa `session_user`, no una GUC configurable por el cliente. |
| RN-14 | `transportista`, `bodega`, `vino` y sus movimientos dependientes | No borrar Transportista, Bodega o Vino con movimientos asociados (texto explícito). | Sí; acción referencial no cambia las claves candidatas. | FK con ON DELETE RESTRICT conservadas para maestros; D1/D5 purgan documentos elegibles, no los maestros referenciados. |
| RN-15 | `vino`, `empleado`, `finca`, `parcela`, `lote_uva`, renglones, stocks y demás medidas | Rangos y positividad requeridos; stocks pueden ser cero, nunca negativos. | Sí; CHECK/rangos son independientes de la prueba de 3FN. | Tipos `numeric`, dominio CUIT y CHECK específicos en el esquema físico. |

## Diferencias y supuestos del TPI

- El XML actual sí contiene `porcentaje_corte`, `cantidad`, `precio`, `descuento_aplicado`, `subtotal` en Comprobante–Vino; `cantidad_botellas` en Ingreso–Vino y Transferencia–Vino; `cantidad_stock` en Sala–Vino; y campos parciales de auditoría. Los informes previos de inventario no estaban actualizados con esta versión.
- El DER marca la ISA como **Total, disjunta**, y el TPI confirma los tres subtipos. Se conserva mediante supertipo, discriminador y subtipos con clave compartida.
- Parcela está gráficamente marcada como entidad débil por su doble contorno (`double=1`) en el DER; la PK `(id_finca, numero_parcela)` y la FK a Finca reflejan esa identificación. Se conserva la relación con Cepa mediante `parcela.id_cepa`.
- El TPI pide datos de zona para Distribuidor; el óvalo `zona_cobertura` está huérfano en el XML. Se asigna a Distribuidor solo por esa regla explícita y queda documentado como complemento, no como conexión del DER.
- El atributo `descuento_10%` también está huérfano. RN-06 asigna la tasa base del 10 % a Socio; `cliente.descuento` guarda el valor vigente por cliente para permitir la actualización explícita de U6.
- `ID_auditoria` y `precio_nuevo` tienen conectores sin destino. Se incorporan a Auditoría de precios por el TPI/RN-13; `precio_nuevo` es requerido para auditar el cambio, y `ID_auditoria` se usa como clave técnica.
- `codigo_postal` está marcado como identificador de Localidad en el XML; reemplaza la clave sustituta `id_localidad` del modelo previo. No se afirma que el código postal sea perfecto como clave natural fuera del alcance del DER: se respeta la identificación marcada.
- Por decisión aprobada, Localidad–Finca es 1:N; `finca.codigo_postal` es FK NOT NULL sin UNIQUE. `Finca.provincia` se elimina de la relación base y se recupera mediante JOIN a Localidad.
- `numero_lote` está marcado como identificador en el XML y es PK. Además, el par parcela/campaña queda `UNIQUE` por RN-04. Esa clave candidata no sustituye al identificador original.
- Se implementan cuatro claves alternativas además de las PK: UNIQUE de `(id_finca, numero_parcela, campania)` en Lote por RN-04; `(nombre_comercial, anada, presentacion_ml)` en Vino según el ejemplo explícito de restricciones del TPI; `(tipo_documento, numero_documento)` en Cliente porque el documento identifica a una persona/entidad dentro de su tipo; y `cuit` en Transportista porque el CUIT identifica al contribuyente. La última pareja de reglas usa la semántica de los atributos identificadores del escenario, no una unicidad de nombre, teléfono o dirección.
- El CUIT de Bodega ya es la PK y, por tanto, ya es único, pero no cuenta como UNIQUE adicional a las PK. No se agrega UNIQUE a nombres de Cepa ni a números de habilitación sin regla que lo justifique.
- Los valores `tinto` y `blanco` se interpretan como valores del atributo `Cepa.tipo`, según el TPI, no como atributos booleanos.
- Por renglón: bruto = cantidad × precio; descuento monetario = bruto × `comprobante.descuento_aplicado` / 100; neto = bruto − descuento. El total de cabecera es la suma de netos y se mantiene automáticamente.
- Al crear una venta se copia `cliente.descuento` a `comprobante.descuento_aplicado`; cambios posteriores del valor vigente no modifican tasas ni totales anteriores. **Decisión aprobada para U1:** recalcular todos los totales usando el descuento histórico guardado en cada comprobante, sin modificarlo.
- Localidad–Finca se modela como 1:N por decisión aprobada: FK NOT NULL, no UNIQUE, en Finca. `Finca.provincia` se recupera mediante JOIN a Localidad y no se duplica.

## Operaciones U1 y U6

U6 actualiza `cliente.descuento` al 35 % para exportadores con más de tres permisos. Al emitir una venta se copia el valor vigente a `comprobante.descuento_aplicado`; la operación U6 no debe propagar cambios a comprobantes ya emitidos.

El enunciado literal de U1 dice: “Recalcular el total de todos los comprobantes aplicando el descuento que corresponde al tipo de cliente”. La decisión aprobada interpreta esa operación como el recálculo con `comprobante.descuento_aplicado`, es decir, la tasa histórica de cada venta. Se mantiene el texto original sin reinterpretarlo: la frase “que corresponde al tipo de cliente” podría entenderse como la tasa vigente actual, interpretación distinta de la aprobada. **Si esa era la intención literal del enunciado, existe una discrepancia entre el TPI y la decisión del proyecto**: aplicar la tasa actual alteraría los totales históricos, mientras que la decisión aprobada prohíbe hacerlo. Para el modelo del proyecto, U1 queda definida y se implementará con la tasa histórica; no se usarán tasas vigentes para recomputar comprobantes anteriores.

Para inventario, los ingresos y transferencias mantienen sus propios documentos y renglones como historial; no se agrega una tabla `movimiento_stock`. El procesamiento afecta saldos una sola vez: ingresos acreditan depósito; transferencias descuentan depósito y acreditan sala. Las operaciones deben validar estado y disponibilidad y actualizar saldos y documento en una transacción atómica.

## Estado de normalización

La matriz de [normalizacion.md](./normalizacion.md) cubre individualmente las 29 relaciones, sus esquemas, claves candidatas, atributos primos/no primos y DF relevantes. Se corrigió la DF parcial `numero_comprobante → descuento_aplicado` trasladando la tasa histórica del renglón a la cabecera. Las 29 relaciones cumplen 3FN respecto de las DF justificadas. `comprobante.total` se almacena como resumen agregado aprobado; su consistencia transaccional es una obligación operativa separada de la prueba de 3FN. La posible diferencia entre el sentido literal de U1 y su interpretación aprobada se documenta arriba y no es una excepción a la normalización.

## Integridad de la especialización Cliente

Se conserva el supertipo `cliente` con `tipo_cliente` y subtipos `socio`, `distribuidor` y `exportador`, con PK/FK compartida. Las FK expresan las referencias, y los triggers diferidos exigen que al cierre de cada transacción exista exactamente el subtipo que indica `tipo_cliente`:

- Cada fila de `cliente` debe tener exactamente una fila correspondiente en el subtipo indicado por `tipo_cliente`.
- No debe existir fila en un subtipo distinto del declarado por `tipo_cliente`, ni filas simultáneas en varios subtipos.
- Las FK compartidas evitan subtipos huérfanos, pero no obligan a que exista un subtipo ni impiden la pertenencia a dos.
- `fn_validar_cliente_isa` y los constraint triggers diferidos en Cliente/subtipos aplican esta validación al insertar, actualizar o borrar. Los cambios en subtipos también bloquean la fila del supertipo para serializar operaciones concurrentes.

La fase B añade `ck_cliente_nombre`: `nombre` contiene nombre personal o razón
social, no puede ser NULL ni quedar vacío al quitar espacios. `apellido` sigue
siendo opcional para no exigir datos personales a empresas. Se conservan los
tres subtipos y sus atributos particulares.

## Correcciones físicas de fase B

Se reutilizan los triggers de cabecera: un documento procesado no admite
cambios efectivos de ningún atributo y un comprobante rechaza un total
inconsistente con cantidad, precio del detalle y descuento histórico. No se
añaden tablas, funciones productivas, triggers ni mecanismos de bypass.

La instalación termina asignando propiedad real de los objetos a
`bodegas_propietario`. Se controla search_path de las funciones SQL que resuelven
objetos propios y se corrigen los defaults de EXECUTE de PUBLIC. El detalle
operativo y la evidencia de las suites están en [database/README.md](../database/README.md#resultado-de-validación-y-alcance).

En B.2 se implementó la política histórica autorizada: D1 elimina cabeceras de
socios de más de cinco años con cascada sin reintegro; D5 elimina ingresos
procesados de más de 365 días sin débito. Borrar directamente un detalle de
venta conserva su reintegro ordinario. Se modifica únicamente la acción DELETE
de la FK de comprobante a detalle, sin quitar la FK ni cambiar claves o 3FN;
el DBML refleja la nueva acción y el DER conceptual permanece intacto.
La excepción de purga frente al texto de RN-12 y su pérdida de historial se
explican en [database/README.md](../database/README.md#eliminación-histórica-d1d5--política-aprobada-en-b2).

## Resultado

El DBML representa las 22 entidades conceptuales y 25 relaciones del DER; el descuento histórico de comprobante se reubica en cabecera por la DF y la normalización demostradas. Localidad–Finca usa la cardinalidad aprobada 1:N y la provincia se recupera por JOIN. El DDL, las funciones, procedimientos y triggers se encuentran en `database/` y las pruebas corridas están resumidas en su README. La interpretación de U1 está aprobada para el proyecto: recalcular con la tasa histórica; la posible discrepancia literal con el TPI queda registrada en esta validación, no pendiente de decisión interna.
