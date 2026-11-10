# Normalización formal del modelo relacional

## Alcance y método

Se revisan individualmente las 29 relaciones de [modelo_relacional.dbml](./modelo_relacional.dbml). Se consideran las claves del esquema, las reglas RN-04/RN-06/U6, las restricciones UNIQUE justificadas por el TPI y las decisiones confirmadas. Las claves alternativas se declaran expresamente en el DBML y en el DDL.

La matriz documenta el esquema de atributos, PK, claves candidatas, atributos primos/no primos y las DF no triviales justificadas. Para cada relación se aplica la prueba formal de 3FN: para toda DF no trivial `X → A`, `X` debe ser superclave o `A` debe ser primo. La conclusión es respecto del conjunto de DF declarado en cada fila; CHECK, FK, triggers e ISA no sustituyen esa prueba.

`P` indica atributos primos (miembros de alguna clave candidata); `NP`, atributos no primos. Además de `lote_uva`, `vino`, `cliente` y `transportista` tienen claves candidatas alternativas justificadas. Una FK no crea por sí misma una DF dentro de la relación hija.

## Matriz de verificación

| Relación / esquema de atributos | PK | Claves candidatas y atributos P / NP | DF no triviales justificadas | 1FN | 2FN | 3FN | Prueba / justificación |
|---|---|---|---|---|---|---|---|
| `localidad(codigo_postal, nombre, provincia, encargado_regional)` | `codigo_postal` | `{codigo_postal}`; P: `codigo_postal`; NP: `nombre, provincia, encargado_regional` | `codigo_postal → nombre, provincia, encargado_regional` | Sí | Sí | Sí | La PK determina todos los NP; no se supone único el nombre ni la provincia. |
| `sala_venta(id_sala, calle, numero, cierre_semanal, codigo_postal)` | `id_sala` | `{id_sala}`; P: `id_sala`; NP: `calle, numero, cierre_semanal, codigo_postal` | `id_sala → calle, numero, cierre_semanal, codigo_postal` | Sí | Sí | Sí | PK simple; no se trasladan atributos de Localidad a Sala. |
| `empleado(cuit, nombre, fecha_laboral, salario, id_sala)` | `cuit` | `{cuit}`; P: `cuit`; NP: `nombre, fecha_laboral, salario, id_sala` | `cuit → nombre, fecha_laboral, salario, id_sala` | Sí | Sí | Sí | PK simple. La FK a sala no establece dependencias adicionales entre atributos de Empleado. |
| `finca(id_finca, nombre, superficie_total, departamento, codigo_postal)` | `id_finca` | `{id_finca}`; P: `id_finca`; NP: `nombre, superficie_total, departamento, codigo_postal` | `id_finca → nombre, superficie_total, departamento, codigo_postal` | Sí | Sí | Sí | `codigo_postal` no es UNIQUE: Localidad–Finca es 1:N. Provincia no se duplica; se recupera mediante JOIN a Localidad. |
| `cepa(id_cepa, nombre, tipo)` | `id_cepa` | `{id_cepa}`; P: `id_cepa`; NP: `nombre, tipo` | `id_cepa → nombre, tipo` | Sí | Sí | Sí | PK simple; no se presume único el nombre. |
| `parcela(id_finca, numero_parcela, superficie_total, anio_plantacion, id_cepa)` | `(id_finca, numero_parcela)` | `{id_finca, numero_parcela}`; P: `id_finca, numero_parcela`; NP: `superficie_total, anio_plantacion, id_cepa` | `(id_finca, numero_parcela) → superficie_total, anio_plantacion, id_cepa` | Sí | Sí | Sí | Entidad débil. No hay DF documentada desde solo `id_finca` o solo `numero_parcela`. |
| `lote_uva(numero_lote, id_finca, numero_parcela, campania, fecha_cosecha, kilos_cosechados, cuit_bodega_destino)` | `numero_lote` | `{numero_lote}` y `{id_finca, numero_parcela, campania}`; P: `numero_lote, id_finca, numero_parcela, campania`; NP: `fecha_cosecha, kilos_cosechados, cuit_bodega_destino` | `numero_lote → id_finca, numero_parcela, campania, fecha_cosecha, kilos_cosechados, cuit_bodega_destino`; `(id_finca, numero_parcela, campania) → numero_lote, fecha_cosecha, kilos_cosechados, cuit_bodega_destino` | Sí | Sí | Sí | PK del DER y clave candidata de RN-04. Cada determinante es clave candidata completa; no hay DF parcial hacia NP. |
| `analisis_calidad(id_analisis, numero_lote, fecha, grado_brix, ph, acidez_total)` | `id_analisis` | `{id_analisis}`; P: `id_analisis`; NP: `numero_lote, fecha, grado_brix, ph, acidez_total` | `id_analisis → numero_lote, fecha, grado_brix, ph, acidez_total` | Sí | Sí | Sí | No se inventa una clave por lote/fecha ni una frecuencia de análisis. |
| `bodega(cuit, razon_social, domicilio)` | `cuit` | `{cuit}`; P: `cuit`; NP: `razon_social, domicilio` | `cuit → razon_social, domicilio` | Sí | Sí | Sí | CUIT es la clave definida para Bodega. |
| `vino(codigo_vino, nombre_comercial, tipo, anada, presentacion_ml, graduacion_alcoholica, precio, cuit_bodega)` | `codigo_vino` | `{codigo_vino}` y `{nombre_comercial, anada, presentacion_ml}`; P: `codigo_vino, nombre_comercial, anada, presentacion_ml`; NP: `tipo, graduacion_alcoholica, precio, cuit_bodega` | `codigo_vino → nombre_comercial, tipo, anada, presentacion_ml, graduacion_alcoholica, precio, cuit_bodega`; `(nombre_comercial, anada, presentacion_ml) → codigo_vino, tipo, graduacion_alcoholica, precio, cuit_bodega` | Sí | Sí | Sí | La clave natural alternativa está indicada como UNIQUE en el TPI; ambos determinantes son claves candidatas completas. |
| `composicion_vino_cepa(codigo_vino, id_cepa, porcentaje_corte)` | `(codigo_vino, id_cepa)` | `{codigo_vino, id_cepa}`; P: ambos; NP: `porcentaje_corte` | `(codigo_vino, id_cepa) → porcentaje_corte` | Sí | Sí | Sí | El porcentaje depende del par completo. La suma 100 % es una restricción agregada, no una DF parcial. |
| `maridaje(id_maridaje, nombre, temperatura_servicio)` | `id_maridaje` | `{id_maridaje}`; P: `id_maridaje`; NP: `nombre, temperatura_servicio` | `id_maridaje → nombre, temperatura_servicio` | Sí | Sí | Sí | No se declara único el nombre. |
| `vino_maridaje(codigo_vino, id_maridaje)` | `(codigo_vino, id_maridaje)` | `{codigo_vino, id_maridaje}`; P: ambos; NP: ninguno | Ninguna con RHS no vacío | Sí | Sí | Sí | Asociación sin atributos no clave; la 2FN/3FN se cumplen vacíamente. |
| `cliente(id_cliente, apellido, nombre, tipo_cliente, tipo_documento, numero_documento, direccion, codigo_postal, descuento, fecha_de_alta)` | `id_cliente` | `{id_cliente}` y `{tipo_documento, numero_documento}`; P: `id_cliente, tipo_documento, numero_documento`; NP: `apellido, nombre, tipo_cliente, direccion, codigo_postal, descuento, fecha_de_alta` | `id_cliente → apellido, nombre, tipo_cliente, tipo_documento, numero_documento, direccion, codigo_postal, descuento, fecha_de_alta`; `(tipo_documento, numero_documento) → id_cliente, apellido, nombre, tipo_cliente, direccion, codigo_postal, descuento, fecha_de_alta` | Sí | Sí | Sí | Se asume que un mismo documento identifica a un solo cliente; `tipo_documento` integra la clave para permitir números iguales bajo documentos de distinto tipo. U6 impide adoptar `tipo_cliente → descuento` como DF universal. |
| `socio(id_cliente)` | `id_cliente` | `{id_cliente}`; P: `id_cliente`; NP: ninguno | Ninguna con RHS no vacío | Sí | Sí | Sí | Relación de subtipo sin atributos propios; cumplimiento vacuo de 2FN/3FN. |
| `distribuidor(id_cliente, zona_cobertura, numero_habilitacion)` | `id_cliente` | `{id_cliente}`; P: `id_cliente`; NP: `zona_cobertura, numero_habilitacion` | `id_cliente → zona_cobertura, numero_habilitacion` | Sí | Sí | Sí | PK compartida con Cliente; no se presume único el número de habilitación. |
| `exportador(id_cliente, pais_destino)` | `id_cliente` | `{id_cliente}`; P: `id_cliente`; NP: `pais_destino` | `id_cliente → pais_destino` | Sí | Sí | Sí | PK compartida con Cliente. |
| `permiso_exportacion(codigo_permiso, id_exportador, fecha_emision, fecha_vencimiento)` | `codigo_permiso` | `{codigo_permiso}`; P: `codigo_permiso`; NP: `id_exportador, fecha_emision, fecha_vencimiento` | `codigo_permiso → id_exportador, fecha_emision, fecha_vencimiento` | Sí | Sí | Sí | El TPI permite varios permisos por exportador; no se inventa clave alternativa por fechas. |
| `comprobante(numero_comprobante, fecha, id_cliente, id_sala, descuento_aplicado, total)` | `numero_comprobante` | `{numero_comprobante}`; P: `numero_comprobante`; NP: `fecha, id_cliente, id_sala, descuento_aplicado, total` | `numero_comprobante → fecha, id_cliente, id_sala, descuento_aplicado, total` | Sí | Sí | Sí* | La PK determina todos los NP; el descuento histórico se conserva una vez por venta. `total` es redundancia agregada con el detalle, no una DF de fila entre atributos no clave; ver análisis específico. |
| `comprobante_vino(numero_comprobante, codigo_vino, cantidad, precio)` | `(numero_comprobante, codigo_vino)` | `{numero_comprobante, codigo_vino}`; P: ambos; NP: `cantidad, precio` | `(numero_comprobante, codigo_vino) → cantidad, precio` | Sí | Sí | Sí | Tras retirar `descuento_aplicado` parcial, ambos NP dependen de la clave completa. Precio histórico por vino y comprobante no determina un precio vigente. |
| `transportista(codigo_transporte, razon_social, cuit, email, telefono, domicilio)` | `codigo_transporte` | `{codigo_transporte}` y `{cuit}`; P: `codigo_transporte, cuit`; NP: `razon_social, email, telefono, domicilio` | `codigo_transporte → razon_social, cuit, email, telefono, domicilio`; `cuit → codigo_transporte, razon_social, email, telefono, domicilio` | Sí | Sí | Sí | El CUIT identifica a un contribuyente; se declara clave candidata adicional. |
| `transportista_localidad(codigo_transporte, codigo_postal)` | `(codigo_transporte, codigo_postal)` | `{codigo_transporte, codigo_postal}`; P: ambos; NP: ninguno | Ninguna con RHS no vacío | Sí | Sí | Sí | Asociación sin atributos no clave; cumplimiento vacuo de 2FN/3FN. |
| `ingreso(codigo_ingreso, fecha, estado, codigo_transporte, cuit_bodega)` | `codigo_ingreso` | `{codigo_ingreso}`; P: `codigo_ingreso`; NP: `fecha, estado, codigo_transporte, cuit_bodega` | `codigo_ingreso → fecha, estado, codigo_transporte, cuit_bodega` | Sí | Sí | Sí | Los detalles repetibles de vinos están en `ingreso_vino`. |
| `ingreso_vino(codigo_ingreso, codigo_vino, cantidad_botellas)` | `(codigo_ingreso, codigo_vino)` | `{codigo_ingreso, codigo_vino}`; P: ambos; NP: `cantidad_botellas` | `(codigo_ingreso, codigo_vino) → cantidad_botellas` | Sí | Sí | Sí | La cantidad depende del par ingreso-vino completo. |
| `transferencia(numero_solicitud, id_sala, fecha_confeccion, estado)` | `numero_solicitud` | `{numero_solicitud}`; P: `numero_solicitud`; NP: `id_sala, fecha_confeccion, estado` | `numero_solicitud → id_sala, fecha_confeccion, estado` | Sí | Sí | Sí | Los productos transferidos se separan en `transferencia_vino`. |
| `transferencia_vino(numero_solicitud, codigo_vino, cantidad_botellas)` | `(numero_solicitud, codigo_vino)` | `{numero_solicitud, codigo_vino}`; P: ambos; NP: `cantidad_botellas` | `(numero_solicitud, codigo_vino) → cantidad_botellas` | Sí | Sí | Sí | La cantidad depende del par solicitud-vino completo. |
| `stock_sala(id_sala, codigo_vino, cantidad_stock)` | `(id_sala, codigo_vino)` | `{id_sala, codigo_vino}`; P: ambos; NP: `cantidad_stock` | `(id_sala, codigo_vino) → cantidad_stock` | Sí | Sí | Sí | No se documenta dependencia desde solo sala o solo vino. |
| `stock_deposito(codigo_vino, cantidad_botellas_disponibles)` | `codigo_vino` | `{codigo_vino}`; P: `codigo_vino`; NP: `cantidad_botellas_disponibles` | `codigo_vino → cantidad_botellas_disponibles` | Sí | Sí | Sí | Una fila de saldo por vino en el depósito central. |
| `auditoria_precios(id_auditoria, codigo_vino, precio_anterior, precio_nuevo, fecha_del_cambio, hora_del_cambio, usuario_modificacion)` | `id_auditoria` | `{id_auditoria}`; P: `id_auditoria`; NP: `codigo_vino, precio_anterior, precio_nuevo, fecha_del_cambio, hora_del_cambio, usuario_modificacion` | `id_auditoria → codigo_vino, precio_anterior, precio_nuevo, fecha_del_cambio, hora_del_cambio, usuario_modificacion` | Sí | Sí | Sí | El identificador de auditoría distingue cambios repetidos; no se presume clave por vino/fecha/hora. |

`Sí*` indica 3FN de `comprobante` respecto de sus DF de fila. La redundancia agregada se evalúa aparte y no se presenta como si un trigger probara normalidad.

## Demostración por forma normal

### Primera forma normal

Cada atributo de las 29 relaciones representa un valor escalar. Las colecciones repetibles se separan en tablas de renglones y asociaciones (`comprobante_vino`, `composicion_vino_cepa`, `vino_maridaje`, `transportista_localidad`, `ingreso_vino`, `transferencia_vino`). No se almacenan listas o grupos repetidos en una celda.

### Segunda forma normal

Las relaciones con claves candidatas simples satisfacen 2FN por definición. En las relaciones con claves compuestas, la matriz identifica todos los atributos no primos y muestra que sus DF requieren la clave candidata completa; no hay DF parcial justificada en las tablas resultantes.

Se detectó una violación antes de la corrección: en `comprobante_vino(numero_comprobante, codigo_vino, cantidad, precio, descuento_aplicado)`, la tasa histórica es uniforme para todos los renglones de una venta. Al crear el comprobante se copia `cliente.descuento` a su cabecera; desde entonces `numero_comprobante → descuento_aplicado`. El determinante es parte propia de la PK compuesta y el RHS no es primo: violaba 2FN y también 3FN. Se trasladó el porcentaje histórico a `comprobante.descuento_aplicado`; ahora la línea conserva solo `cantidad` y `precio`, que dependen del par completo. Esta DF histórica no implica `id_cliente → descuento_aplicado`: un cliente puede cambiar su descuento vigente y conservar tasas distintas en comprobantes emitidos en momentos diferentes.

Todos los renglones de una venta usan la tasa guardada en la cabecera; no se admiten tasas diferentes por vino dentro del mismo comprobante.

### Tercera forma normal

Para cada fila de la matriz, las DF relevantes son las determinadas por las claves candidatas completas de esa relación. Todo atributo no primo depende de una clave completa y no existe en el esquema resultante una DF no trivial documentada con determinante no-superclave y RHS no primo. Las asociaciones puras no tienen atributos no primos, por lo que satisfacen 3FN vacíamente.

Las decisiones confirmadas eliminan la posible dependencia cruzada de `Finca.provincia`: esa columna ya no existe en `finca`; se obtiene a través de `finca.codigo_postal → localidad.codigo_postal → localidad.provincia`. El código postal no es único en Finca, de acuerdo con la cardinalidad Localidad 1:N Finca. En `cliente`, `id_cliente → descuento`; no se postula `tipo_cliente → descuento` para el valor vigente porque U6 lo modifica selectivamente.

La demostración cubre las DF justificadas por las claves primarias y alternativas documentadas. No se infieren dependencias de teléfonos, fechas u otros atributos sin regla de unicidad. Las referencias FK y restricciones de negocio no crean DF adicionales dentro de tablas hijas salvo que una clave alternativa local las establezca.

## Descomposición sin pérdida y preservación

### Descuento histórico del comprobante

Relación de detalle anterior:

`R(numero_comprobante, codigo_vino, cantidad, precio, descuento_aplicado)`

Con la dependencia justificada `numero_comprobante → descuento_aplicado`, se descompone en:

- `R1(numero_comprobante, codigo_vino, cantidad, precio)` — `comprobante_vino`.
- `R2(numero_comprobante, descuento_aplicado)` — incorporada como atributo de `comprobante`, cuya PK es `numero_comprobante`.

La intersección es `{numero_comprobante}` y determina todos los atributos de `R2`, cuya clave es `numero_comprobante`; por el criterio de intersección-clave, la descomposición es **sin pérdida**. La dependencia `numero_comprobante → descuento_aplicado` se preserva en `comprobante`; la dependencia de la clave compuesta hacia `cantidad, precio` se preserva en `comprobante_vino`. El descuento histórico continúa recuperable por JOIN y no cambia al actualizar `cliente.descuento`.

### Provincia de Finca

Relación anterior:

`Finca_original(id_finca, nombre, superficie_total, departamento, codigo_postal, provincia)`

Con la decisión aprobada de que cada finca tiene exactamente una Localidad y su provincia es la de esa Localidad, se cumple `codigo_postal → provincia` en la proyección anterior. Se descompone en:

- `Finca(id_finca, nombre, superficie_total, departamento, codigo_postal)`.
- `Localidad(codigo_postal, nombre, provincia, encargado_regional)`.

La intersección `{codigo_postal}` es clave de `Localidad`; por tanto, la reunión es **sin pérdida** respecto de esa regla semántica. Las dependencias de Finca determinadas por `id_finca` se preservan en Finca, y `codigo_postal → provincia` se preserva en Localidad. La FK NOT NULL garantiza que toda Finca pueda recuperar provincia mediante JOIN. `Finca.provincia` se elimina del DBML.

No se realizó otra descomposición: las demás relaciones satisfacen 3FN según sus DF justificadas.

## Total materializado y 3FN

`comprobante.total` se almacena por la decisión operativa confirmada. Dentro de `comprobante`, `numero_comprobante → total`, así que no hay una DF de fila con determinante no-superclave que viole 3FN. El total, sin embargo, es también una función agregada de los renglones (precio, cantidad y descuento histórico); mantener ambos valores crea **redundancia entre relaciones**.

La suma sobre varias filas no es una DF clásica entre columnas de una tupla y no se usa como prueba de 3FN. Las funciones y triggers implementados mantienen igualdad transaccional entre resumen y detalle ante cambios y borrados; esas garantías son de integridad operativa, no evidencia de normalización. No se afirma que la redundancia agregada desaparezca, solo que, bajo la definición relacional de 3FN por DF de cada relación base, `comprobante` cumple la forma.

## Descuento vigente, descuento histórico y U1

`cliente.descuento` conserva el porcentaje vigente por cliente. RN-06 define las tasas iniciales por subtipo y U6 permite subir selectivamente al 35 % a exportadores con más de tres permisos. Por ello, para el valor vigente no se sostiene la DF universal `tipo_cliente → descuento`; sí se sostiene `id_cliente → descuento`.

Al crear una venta, `comprobante.descuento_aplicado` recibe una copia del valor vigente de `cliente.descuento`. La tasa queda fijada para ese comprobante y todos sus renglones; una actualización posterior de `cliente.descuento` no debe propagar cambios a comprobantes anteriores. No se sostiene una DF entre `id_cliente` y las tasas históricas a través del tiempo; dentro de `comprobante`, la clave `numero_comprobante` determina su tasa almacenada.

La interpretación aprobada de U1 para el proyecto es recalcular todos los totales usando `comprobante.descuento_aplicado`, sin modificar esa tasa. Por tanto, los recálculos ordinarios y U1 preservan el historial. La frase literal del TPI —“aplicando el descuento que corresponde al tipo de cliente”— puede leerse como el descuento vigente al ejecutar la operación; esa diferencia textual queda registrada en `validacion_tpi.md`, sin cambiar ni reinterpretar el enunciado.

## Otras restricciones: no son pruebas de 3FN

- `Localidad 1:N Finca`: FK NOT NULL en Finca, no UNIQUE.
- `Parcela` es débil, con PK `(id_finca, numero_parcela)`.
- `lote_uva`: `numero_lote` PK y UNIQUE `(id_finca, numero_parcela, campania)` según RN-04.
- Claves alternativas adicionales: UNIQUE de `(nombre_comercial, anada, presentacion_ml)` en Vino según el ejemplo del TPI; `(tipo_documento, numero_documento)` en Cliente; y `cuit` en Transportista. El CUIT de Bodega ya es su PK.
- `composicion_vino_cepa`: sumatoria por vino igual a 100 % es una restricción agregada.
- ISA total/disjunta requiere comprobar exactamente un subtipo coherente con el discriminador.
- Positividad, rangos, fechas y estados son restricciones CHECK/temporales.
- Stock suficiente y no negativo es integridad entre movimientos y saldos.
- Procesar ingresos/transferencias una sola vez, de forma transaccional, y auditar cambios efectivos de precio son automatizaciones operativas.

## Resultado formal

**Las 29 relaciones base resultantes cumplen 3FN respecto de las dependencias funcionales justificadas y enumeradas.** Se corrigió la violación de 2FN/3FN en el detalle del comprobante mediante una descomposición sin pérdida y con dependencias preservadas. Se eliminó `Finca.provincia` y se recupera desde Localidad mediante una descomposición sin pérdida bajo las decisiones confirmadas. `comprobante.total` es una redundancia agregada aprobada, mantenida operativamente; no se presenta el trigger como prueba de normalización.

La interpretación aprobada de U1 requiere que la operación use la tasa histórica de cada comprobante y no modifique ventas previas. La posible diferencia con la frase literal del TPI está documentada en `validacion_tpi.md` y no afecta la verificación de 3FN.
