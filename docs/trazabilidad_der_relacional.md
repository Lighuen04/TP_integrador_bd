# Trazabilidad del DER al modelo relacional

## Fuentes y alcance

- DER consultado con autorización del usuario: `C:\Users\eluam\Downloads\DER.drawio.xml`.
- Requisitos consultados con autorización del usuario: `C:\Users\eluam\Downloads\TPI_Bodegas_del_Atuel.md`.
- Modelo resultante: [modelo_relacional.dbml](./modelo_relacional.dbml).

El inventario previo registra dos páginas en el XML: la página 1 contiene el diagrama y la página 2 solo celdas raíz. Los rótulos de cardinalidad son vértices de texto sin vínculo estructural a los conectores. La cardinalidad aprobada para Localidad–Finca es 1:N y prevalece sobre la lectura visual anterior. El archivo DBML documenta el modelo lógico; la implementación SQL ejecutable está en `database/`.

## Inventario comprobado del XML

| Página | Celdas XML | Vértices | Entidades | Relaciones | Óvalos de atributos | Rótulos 1/N/M | Conectores |
|---|---:|---:|---:|---:|---:|---:|---:|
| Página 1 | 347 | 193 | 22 | 25 | 97 | 48 | 152 |
| Página 2 | 2 | 0 | 0 | 0 | 0 | 0 | 0 |

Hay un nodo ISA etiquetado “Total disjunta”. Los 48 rótulos `1`, `N` y `M` son vértices de texto sin conectores XML; su asociación a los extremos debe leerse visualmente y no se conserva como dato estructurado. Para Localidad–Finca se aplica la decisión aprobada de 1:N; en las demás relaciones se usa el TPI cuando especifica cardinalidad y se explicitan las interpretaciones.

## Entidades y atributos

La columna “atributos del DER” enumera todos los óvalos ligados a cada entidad. Cuando una etiqueta no se convierte en una columna literal, se explica su representación.

| Entidad DER | Atributos del DER | Representación en el modelo / diferencia |
|---|---|---|
| Localidad | `nombre`, `provincia`, `codigo_postal`, `encargado_regional` | `localidad`; `codigo_postal` es la clave primaria porque el óvalo está marcado como identificador en el DER (estilo subrayado/fontStyle). No se agrega `id_localidad`. |
| Sala de venta | `ID_sala`, `calle`, `numero`, `cierre_semanal` | `sala_venta`; FK a localidad. |
| Empleados | `CUIT`, `nombre`, `salario`, `fecha_laboral` | `empleado`; CUIT PK y FK a sala. |
| Finca | `ID_finca`, `nombre`, `superficie_total`, `departamento`, `provincia` | `finca`; `codigo_postal` es FK NOT NULL a Localidad para la relación 1:N aprobada. `provincia` se recupera mediante JOIN a Localidad y no se duplica en la tabla. |
| Parcela | `numero_parcela`, `superficie_total`, `año_plantacion` | `parcela`; doble contorno (`double=1`) la representa gráficamente como entidad débil. PK `(id_finca, numero_parcela)` y FK a finca; conserva también la relación con Cepa. |
| Cepa | `ID_cepa`, `nombre`, `tipo`, `tinto`, `blanco` | `cepa.tipo` conserva valores `tinta`/`blanca`; `tinto` y `blanco` se interpretan como opciones del dominio, no como banderas independientes. Si esa lectura es incorrecta, hace falta corregir el DER. |
| Lote de uva | `numero_lote`, `campaña`, `fecha_cosecha`, `kilos_cosechados` | `lote_uva`; `numero_lote` está marcado como identificador en el DER y es PK. UNIQUE (`id_finca`, `numero_parcela`, `campania`) implementa el máximo de una cosecha por parcela/campaña de RN-04; FK a parcela y bodega. |
| Análisis de calidad | `ID_analisis`, `fecha`, `grado_brix`, `pH`, `acidez_total` | `analisis_calidad`; FK a `numero_lote`. |
| Bodega | `CUIT`, `razon_social`, `domicilio` | `bodega`; CUIT PK. |
| Vino | `codigo_vino`, `nombre_comercial`, `tipo`, `añada`, `presentacion`, `graduacio_alcoholica`, `precio` | `vino`; presentación se expresa en ml y graduación en `numeric`; FK a bodega. |
| Maridaje | `ID_maridaje`, `nombre`, `temperatura_servicio` | `maridaje`; temperatura `numeric`. |
| Cliente | `ID_cliente`, `apellido`, `nombre`, `tipo_documento`, `numero_documento`, `direccion`, `localidad`, `descuento`, `fecha_de_alta` | `cliente`; `localidad` se representa por FK y `descuento` se conserva como valor vigente por cliente. U6 permite actualizarlo al 35 %; no se asume que dependa solo del subtipo. |
| Socio | No tiene atributo conectado | `socio` comparte PK/FK con Cliente; RN-06 establece tasa base del 10 %, y el valor vigente se conserva en `cliente.descuento`. |
| Distribuidor | `numero_habilitacion`, `descuento_20%` | `distribuidor`; se agrega `zona_cobertura` por el TPI; RN-06 establece tasa base del 20 %, cuyo valor vigente se conserva en Cliente. |
| Exportador | `pais_destino`, `descuento_30%` | `exportador`; RN-06 establece tasa base del 30 % y U6 permite actualizar el valor vigente al 35 %. |
| Permiso de Exportación | `codigo_permiso`, `fecha_emision`, `fecha_vencimiento` | `permiso_exportacion`; FK a exportador. |
| Comprobante | `numero_comprobante`, `fecha`, `subtotal`, `descuento`, `total` | `comprobante`; conserva `descuento_aplicado` histórico y `total` como resumen agregado mantenido automáticamente. Los subtotales se calculan. |
| Transportista | `codigo_transporte`, `razon_social`, `CUIT`, `email`, `telefono`, `domicilio` | `transportista`; código PK. CUIT se conserva como atributo, sin agregar UNIQUE no declarado. |
| Ingreso | `codigo_ingreso`, `fecha`, `estado` | `ingreso`; estado usa el enum compartido con Transferencia, más FKs a transportista y bodega. |
| Transferencia | `numero_solicitud`, `fecha_confeccion`, `estado` | `transferencia`; FK a sala; el atributo sala proviene de la relación `solicita`. |
| Stock depósito | `cantidad_botellas_disponibles` | `stock_deposito`; `codigo_vino` como PK/FK, una fila por vino según el TPI. |
| Auditoría de precios | `precio_anterior`, `fecha_del_cambio`, `hora_del_cambio`, `usuario_modificacion` | `auditoria_precios`; se añaden los dos óvalos huérfanos `ID_auditoria` y `precio_nuevo`, necesarios para identificar y completar la auditoría solicitada en RN-13. |

**Nota:** Bodega aparece una sola vez en el esquema, aunque se liste junto a cada entidad/ruta en el DER; no se duplica como concepto.

## Atributos de relaciones

| Relación DER | Atributos conectados | Representación |
|---|---|---|
| Comprobante — incluye — Vino | `cantidad`, `precio`, `descuento_aplicado`, `subtotal` | `comprobante_vino` conserva cantidad y precio históricos; al crear la cabecera se copia `cliente.descuento` a `comprobante.descuento_aplicado`, tasa histórica común a sus renglones. El subtotal bruto calculado por renglón es `cantidad × precio`; el descuento monetario es `subtotal_bruto × descuento_aplicado / 100`, y el importe neto es `subtotal_bruto − descuento_monetario`. Estos importes por renglón se derivan, no se persisten. `comprobante.total = SUM(cantidad × precio) × (1 − descuento_aplicado / 100)` y se mantiene automáticamente. |
| Cepa — se compone de — Vino | `porcentaje_corte` | `composicion_vino_cepa`; PK compuesta y constraint trigger diferido que valida que la suma por vino sea exactamente 100 %. |
| Sala — dispone de — Vino | `cantidad_stock` | `stock_sala`; PK compuesta sala-vino. |
| Ingreso — contiene — Vino | `cantidad_botellas` | `ingreso_vino`; PK compuesta ingreso-vino. |
| Transferencia — contiene — Vino | `cantidad_botellas` | `transferencia_vino`; PK compuesta transferencia-vino. |

## Relaciones, cardinalidades y transformación

Los nombres son las etiquetas de los rombos del XML. El TPI define varias cardinalidades de forma textual; donde no lo hace, se documenta la lectura del DER. Los rótulos `1`, `N` y `M` son elementos de texto sin conectores a los extremos, por lo que no se pueden validar automáticamente como atributos de cardinalidad. Para Localidad–Finca se aplica la decisión confirmada 1:N (Localidad 1, Finca N), que prevalece sobre la lectura anterior.

| Relación | Extremos | Cardinalidad aplicada | Tabla/FK resultante | Evidencia / advertencia |
|---|---|---:|---|---|
| reside en | Cliente — Localidad | Localidad 1:N Cliente | `cliente.codigo_postal` | La dirección/localidad del cliente la exige el TPI; `codigo_postal` es clave de Localidad. |
| posee | Exportador — Permiso | Exportador 1:N Permiso | `permiso_exportacion.id_exportador` | El TPI permite varios permisos por exportador. |
| contiene | Localidad — Finca | Localidad 1:N Finca | `finca.codigo_postal` FK NOT NULL, no UNIQUE | Decisión aprobada: cada finca referencia una localidad y una localidad puede tener varias fincas. |
| contiene | Finca — Parcela | Finca 1:N Parcela | `parcela.id_finca` | Parcela tiene doble contorno en el DER y se representa con PK débil `(id_finca, numero_parcela)`. |
| contiene | Parcela — Cepa | Cepa 1:N Parcela | `parcela.id_cepa` | El TPI dice que cada parcela planta una sola cepa. |
| tiene | Sala — Localidad | Localidad 1:N Sala | `sala_venta.codigo_postal` | El TPI establece que cada sala está en una localidad y una localidad puede tener varias salas. |
| emplea | Sala — Empleados | Sala 1:N Empleado | `empleado.id_sala` | Cada empleado trabaja en una sola sala. |
| registra | Sala — Comprobante | Sala 1:N Comprobante | `comprobante.id_sala` | Cada comprobante corresponde a una sala. |
| realiza | Cliente — Comprobante | Cliente 1:N Comprobante | `comprobante.id_cliente` | Un comprobante pertenece a un cliente. |
| incluye | Comprobante — Vino | N:M | `comprobante_vino` | La relación trae cuatro atributos; el TPI confirma renglones y clave compuesta. |
| produce | Parcela — Lote de uva | Parcela 1:N Lote | `lote_uva.(id_finca, numero_parcela)` | `numero_lote` es PK según marca del DER; UNIQUE parcela/campaña es una restricción adicional requerida por RN-04. |
| se entrega a | Lote de uva — Bodega | Bodega 1:N Lote | `lote_uva.cuit_bodega_destino` | El TPI identifica bodega destinataria del lote. |
| elabora | Vino — Bodega | Bodega 1:N Vino | `vino.cuit_bodega` | El TPI indica una bodega elaboradora por vino. |
| registra cambios | Vino — Auditoría de precios | Vino 1:N Auditoría | `auditoria_precios.codigo_vino` | El TPI/RN-13 exige auditar cada cambio. |
| recomienda | Vino — Maridaje | N:M | `vino_maridaje` | El TPI describe varios maridajes por vino y reutilizables entre vinos. |
| se compone de | Cepa — Vino | N:M | `composicion_vino_cepa` | El TPI confirma N:M y porcentaje por par. |
| tiene registro | Vino — Stock depósito | Una fila por vino (participación mínima pendiente) | `stock_deposito.codigo_vino` | El TPI pide stock central por vino; no especifica si debe existir una fila para cada vino antes de movimientos. |
| recibe | Lote — Análisis de calidad | Lote 1:N Análisis | `analisis_calidad.numero_lote` | El TPI pide uno o más análisis por lote. |
| origina | Bodega — Ingreso | Bodega 1:N Ingreso | `ingreso.cuit_bodega` | Cada ingreso identifica bodega de origen. |
| cubre | Localidad — Transportista | N:M interpretada | `transportista_localidad` | El TPI describe cobertura de transportistas por localidades; cardinalidad mínima y dirección exacta de cada rótulo gráfico requieren confirmación. |
| traslada | Transportista — Ingreso | Transportista 1:N Ingreso | `ingreso.codigo_transporte` | Un transportista designado por ingreso. |
| dispone de | Sala — Vino | N:M interpretada | `stock_sala` | El TPI exige stock por cada combinación sala-vino; cantidad como atributo del registro de stock. |
| solicita | Sala — Transferencia | Sala 1:N Transferencia | `transferencia.id_sala` | Cada transferencia identifica la sala solicitante. |
| contiene | Ingreso — Vino | N:M | `ingreso_vino` | Cantidad de botellas es atributo del renglón según TPI. |
| contiene | Transferencia — Vino | N:M | `transferencia_vino` | Cantidad de botellas es atributo del renglón según TPI. |

## Jerarquía ISA

El XML conecta Cliente con Socio, Distribuidor y Exportador mediante un nodo ISA que dice “Total disjunta”. La estrategia es supertipo más subtipos con clave compartida:

- `cliente` mantiene los atributos comunes y el discriminador `tipo_cliente`.
- `socio`, `distribuidor` y `exportador` usan `id_cliente` como PK/FK.
- La restricción de que cada Cliente aparezca en exactamente un subtipo es total y disjunta; DBML representa las tablas y relaciones, pero la regla necesita validación entre filas en el DDL.
- `zona_cobertura` es un óvalo huérfano en el XML y se asigna a Distribuidor porque el apartado 3.4 del TPI lo exige allí.

## Elementos incompletos o de interpretación

| Elemento XML | Situación observada | Tratamiento explícito |
|---|---|---|
| `zona_cobertura` | Óvalo con una arista sin destino | Se asigna a Distribuidor por el TPI; complemento no conectado en el DER. |
| `descuento_10%` | Óvalo con una arista sin destino | RN-06 asigna el 10 % como valor base de Socio; `cliente.descuento` conserva el porcentaje vigente individual para permitir la actualización de U6. |
| `ID_auditoria` | Óvalo sin extremo de destino | Se usa como PK técnica de Auditoría de precios. |
| `precio_nuevo` | Óvalo con arista sin destino | Se asigna a Auditoría para completar RN-13. |
| `Finca.provincia` | Atributo del DER además de `Localidad.provincia` | Por decisión confirmada se omite de Finca y se recupera mediante JOIN a Localidad. La FK NOT NULL garantiza localidad asociada; la dependencia y descomposición sin pérdida se justifican en `normalizacion.md`. |
| `Cepa.tinto`, `Cepa.blanco` | Óvalos conectados además de `tipo` | Se interpretan como opciones del dominio `tipo`; no se almacenan como dos booleanos redundantes. |
| `Cliente.descuento`, `descuento_20%`, `descuento_30%` | Tasas base explícitas por subtipo; U6 admite 35 % para exportadores con más de tres permisos | `cliente.descuento` conserva el estado vigente por cliente. Por U6 no se afirma `tipo_cliente → descuento` como dependencia funcional universal. |
| Importes de cabecera y `subtotal` de renglón | `total`, subtotal y descuento de cabecera y subtotal de renglón son importes derivados | `comprobante.total` se almacena como resumen agregado mantenido automáticamente. Por renglón, subtotal bruto = `cantidad × precio`, descuento = `subtotal_bruto × descuento_aplicado / 100` e importe neto = `subtotal_bruto − descuento`; son valores calculables y no se persisten. La suma de importes netos equivale al total de cabecera. |
| `Localidad — Finca` | Asociación dibujada; cardinalidad fijada por decisión confirmada como Localidad 1:N Finca | DBML usa `finca.codigo_postal` como FK NOT NULL sin UNIQUE. La decisión confirmada prevalece sobre la lectura visual anterior de rótulos independientes. |
| `Finca.provincia` | Atributo del DER eliminable por decisión confirmada de igualdad con la provincia de la Localidad obligatoria | Se elimina de `finca` y se recupera por JOIN mediante `codigo_postal`. `codigo_postal → provincia` permite la descomposición sin pérdida que se demuestra en `normalizacion.md`. |
| Importes de renglón y comprobante | Subtotal, descuento y total del DER/TPI | Al crear un comprobante se copia el valor vigente de `cliente.descuento` a `comprobante.descuento_aplicado`. El bruto por renglón es cantidad × precio; todos los renglones usan la tasa histórica de cabecera y el total se calcula como `SUM(cantidad × precio) × (1 - descuento_aplicado / 100)`. No se duplica la tasa en los detalles. |
| Etiquetas `1/N/M` | 48 vértices de texto sin aristas | No se pueden asociar de forma inequívoca por estructura XML. Las cardinalidades aplicadas se completan con el TPI y los supuestos se marcan arriba. |

## Claves técnicas frente a claves del modelo

- Se conservan las marcas de identificador del DER disponible: `codigo_postal` en Localidad, `ID_cliente`, `ID_finca`, `codigo_permiso` y `numero_lote`. Para las demás entidades, las claves se apoyan en sus atributos ID/CUIT/código indicados por DER/TPI; las decisiones están en [esquema_relacional.md](./esquema_relacional.md).
- Parcela tiene doble contorno en el DER; usa la clave débil `(id_finca, numero_parcela)`.
- Lote conserva `numero_lote` como PK marcada, y tiene adicionalmente UNIQUE `(id_finca, numero_parcela, campania)` por RN-04.
- `codigo_postal` es PK de Localidad; no se agrega `id_localidad`.
- Auditoría usa `ID_auditoria` del XML aunque su óvalo no esté conectado.

## Conclusión de correspondencia

Las 22 entidades, 25 relaciones y 97 óvalos de atributo se inventariaron. Los campos huérfanos, atributos calculados, claves preservadas, transformaciones y cardinalidades interpretadas se registran expresamente. No se identifican entidades conceptuales eliminadas. Se aplican las decisiones aprobadas: Localidad 1:N Finca, provincia de Finca derivada por JOIN, Parcela débil y descuento histórico copiado a la cabecera al crear cada comprobante. La normalización formal de las 29 relaciones está en `normalizacion.md`; `comprobante.total` conserva redundancia agregada autorizada y requiere consistencia transaccional. U1 se interpreta para el proyecto como recálculo con la tasa histórica; la posible discrepancia con el enunciado literal está documentada en `validacion_tpi.md`.
