# Implementación PostgreSQL — Bodegas del Atuel

## Alcance y fuentes

Estos scripts implementan físicamente el modelo de 29 tablas de
[`../docs/modelo_relacional.dbml`](../docs/modelo_relacional.dbml), sin modificar
el DER ni agregar entidades de negocio. El esquema físico se instala en
`bodegas_atuel`, para aislar sus objetos y permisos. Se requiere PostgreSQL 14 o
superior y privilegios para crear esquemas, tipos, dominios y roles.

El TPI y los documentos lógicos de `docs/` son las referencias funcionales. Los
scripts no cargan datos de producción.

La Etapa 3 está implementada por separado en [`seed/README.md`](seed/README.md):
generador Python con CSV y COPY, validación, reproducibilidad y comparación de
inserción. La carga de prueba llena las 29 tablas y no cambia este DDL ni sus
reglas. La excepción de importación de fechas históricas está acotada y
documentada allí; no es una ruta operativa de la API.

## Consultas SQL — Fase D

Las 30 consignas están en [`../consultas/`](../consultas/): `update.sql`,
`insert.sql`, `delete.sql` y `select.sql`. Probar sobre una base descartable
restaurada desde el dump de fase C, como se explica en
[`seed/README.md`](seed/README.md#dump-comprimido). No hace falta cambiar el
esquema, las reglas ni los índices. Las modificaciones terminan en ROLLBACK,
cada una en su propia transacción; SELECT solo consulta. Mantener ON_ERROR_STOP.

```powershell
$env:PGHOST = '127.0.0.1'
$env:PGPORT = '55441'
$env:PGDATABASE = 'bodegas_d_pruebas'
$env:PGUSER = '<cuenta autorizada>'
psql -X -v ON_ERROR_STOP=1 -c 'SET ROLE bodegas_propietario' -f consultas/update.sql
psql -X -v ON_ERROR_STOP=1 -c 'SET ROLE bodegas_propietario' -f consultas/insert.sql
psql -X -v ON_ERROR_STOP=1 -c 'SET ROLE bodegas_propietario' -f consultas/delete.sql
psql -X -v ON_ERROR_STOP=1 -c 'SET ROLE bodegas_propietario' -f consultas/select.sql
```

Ese es el orden recomendado, aunque los ROLLBACK hacen independientes los casos.
Los parámetros se editan en los `\set` del encabezado de cada archivo: bodega
`20200000001`, cliente 1, vino `V001`, transportista `T1`, sala 1 para venta y
compradores, sala 6 para ausencia de stock, sala 2/General Alvear (`5620`) para
borrado de empleados. Las PK de comprobante/ingreso y de sala/maridaje **no**
tienen identity: se usan números nuevos `TPI-I3`/`TPI-I6`, y MAX+1 bajo bloqueo
para sala/maridaje. Los valores nuevos de I4/I5 son fixtures válidos, no datos
reales de otra bodega. Una colisión de PK provoca error y rollback; no se oculta.

Períodos: semana y quince días incluyen hoy y las seis/catorce fechas anteriores.
Mes y trimestre son ventanas móviles desde CURRENT_DATE menos un mes/tres meses
hasta hoy inclusive. I1/S7 miden actividad por cantidad de ingresos asociados,
sin filtrar estado, y no por botellas ni transferencias. I1 desempata por código
descendente (T4), S7 por ascendente (T1); si el candidato I1 ya cubre la localidad,
ON CONFLICT evita duplicar y no elige artificialmente un transportista de mayor
actividad. S4 cuenta unidades solicitadas en todos los estados.

U1 reutiliza la función autorizada y conserva el descuento histórico: sigue
vigente la discrepancia documentada con la frase literal «por tipo de cliente».
U2 usa fecha estricta: cinco años y un día ya califica aunque la función de años
enteros devuelva cinco. I2 reutiliza un maridaje existente por su menor ID y no
duplica asociaciones. I3 copia precios actuales al detalle histórico; sus
triggers mantienen descuento, total y stock. La revisión E conserva los tres
vinos solicitados mediante VALUES y LEFT JOIN: si falta alguno, los controles
existentes rechazan la venta en vez de omitir un renglón (en la prueba actuó
primero el trigger de stock, SQLSTATE 23514). I6 no se procesa ni aumenta stock.
D1/D5 mantienen la política B.2 sin compensaciones ni bypass. Las restantes FK
pueden impedir una eliminación si cambian las relaciones del dataset; se debe
informar ese error, no desactivar controles ni ampliar el filtro.

S2/S12 usan división con verdad vacía: sin salas o sin vinos exigidos,
respectivamente, todos los elementos del universo candidato cumplen. S3 incluye
tipos con cero compradores; S5 incluye salas con cero pendientes y todos los
empates. S9 agrega por separado cepas y maridajes y usa la vista de stock. S10
compara promedios simples de rendimiento por finca en la misma campaña. S11
conserva empates con RANK y acumula los meses con ventas, sin inventar meses.

### Resultados reales de las consultas

Ejecución en PostgreSQL 18.4, 9/11/2026, base `bodegas_d_pruebas` restaurada de
fase C (semilla 42). Los cuatro archivos finalizaron con código 0.

| Operación | Filas afectadas / resultado |
|---|---:|
| U1 | 100.001 comprobantes recalculados, cero inconsistencias |
| U2 | 9 empleados |
| U3 | 10 vinos y 10 auditorías |
| U4 | 4 salas |
| U5 | 10 vinos y 10 auditorías |
| U6 | 1.667 descuentos vigentes cambiados; historia intacta |
| I1 | 1 cobertura (T4–General Alvear) |
| I2 | 1 maridaje y 10 asociaciones |
| I3 | 1 comprobante y 3 renglones; total 3.267,00 |
| I4 / I5 | 1 bodega / 1 sala |
| I6 | 1 ingreso y 1 renglón de 120 botellas; stock intacto |
| D1 / D2 / D3 | 1.667 comprobantes / 2 cepas / 3 empleados |
| D4 / D5 / D6 | 333 socios / 4 ingresos / 333 socios |
| S1 / S2 / S3 | 10 vinos / 36 vinos / 3 tipos |
| S4 / S5 / S6 | 1 sala (20 botellas) / 6 salas / 5 vinos |
| S7 / S8 / S9 | 1 transportista / 6 salas / 1 ficha |
| S10 | 120 rendimientos de parcela/campaña |
| S11 | 216 posiciones y 48 acumulados mensuales |
| S12 | 0 clientes en división; 1.906 sin compras de tintos |

S12 primera parte vacía es válida: la bodega contiene un vino nunca vendido.
Las consultas devuelven menos de cinco/diez filas si no existen tantos candidatos;
no se agregan resultados ficticios. Los períodos usan CURRENT_DATE: estos conteos
pueden cambiar cuando se ejecuten otro día o con otros parámetros/datos.

Se verifican resultados y rollback contra las 29 huellas de la carga; se comprueban
precios, tasas y stocks por fila, además de los conteos. Los logs completos se
guardan localmente en `.local/fase_d_*.log`, sin versionar miles de resultados.
Se contrastaron agregaciones, divisiones, rendimientos y ventanas con cálculos
independientes sobre los datos fuente. Diez casos límite pasaron: U2 en el
límite exacto y un día posterior, I2 sin candidatos y repetida sin duplicados,
I3 fallando en el segundo renglón sin dejar cabecera/stock, S9 con dos cepas y
dos maridajes, S5 con dos salas de cero pendientes, S2 con sala sin ventas,
S3 sin compradores y en su límite semanal con cliente repetido, RANK con empate
y S12 con universo vacío de vinos. Los fixtures también se revirtieron.
Se ejecutaron los seis planes EXPLAIN (ANALYZE, BUFFERS) de S9–S12 (S11/S12
tienen dos resultados), guardados en `.local/fase_d_planes.log`, con los índices
existentes. No constituyen una comparación antes/después ni prueban una mejora.
ROLLBACK revierte filas, pero las secuencias PostgreSQL pueden avanzar al generar
auditorías. Por eso las pruebas usan la copia descartable y no reinician ni
modifican las secuencias de las bases de referencia. La fase D no añadió funciones,
procedimientos ni índices. Su revalidación E queda conservada en
[`fase_d_consultas.json`](../docs/evidencias/fase_d_consultas.json), incluidos
el caso I1 de mínimo ya cubierto y la regresión I3 de vino inexistente.

## Índices y rendimiento — Fase E

La etapa 4 está completada en el
[único informe de rendimiento](../docs/informe_rendimiento_indices.md), con
planes completos, medianas, buffers, índices usados, costo de escritura y BRIN
descartado en [la evidencia JSON](../docs/evidencias/fase_e_indices.json).
Se mantienen 21 índices originales; dos son sustituidos por versiones que
cubren sus prefijos y se incorpora un parcial (24 secundarios en total).
La mejora queda demostrada en S2, S3 y D4. El parcial de pendientes no se utiliza
con 18 transferencias: se conserva por el requisito explícito del TPI, sin
atribuirle una aceleración que no se observó. Tampoco se prometen mejoras de
los reportes que mantuvieron Seq Scan.

Para aplicar las sustituciones a una instalación existente, usar su cuenta
autorizada y ejecutar `psql -X -v ON_ERROR_STOP=1 -c 'SET ROLE
bodegas_propietario' -f database/06_indices.sql`. El script solo retira los dos
secundarios sustituidos; no elimina tablas, PK ni UNIQUE. Se verificó su
reejecución sin duplicados. Las bases originales no se actualizaron durante el
benchmark: se midió exclusivamente `bodegas_e_medicion`, copia del dump C.
Para reproducir A/B, seguir los comandos del informe; el runner reutiliza las
dependencias de carga y acepta solo bases de prueba identificadas `bodegas_e_*`.

## Orden de ejecución

La [API de fase F](../api/README.md) reutiliza estas reglas con un login miembro
de `bodegas_api`. Después de `01`–`07`, instalar también
`10_api_baja_vino.sql` para su endpoint de baja: una función acotada elimina el
saldo de depósito cero creado automáticamente para un vino sin movimientos.
No modifica tablas ni concede escritura directa sobre stock. Las FK conservan
el rechazo de bajas con dependencias; la suite HTTP prueba éxito y rollback.
Las bases de referencia anteriores no se migraron durante las pruebas F.

Ejecutar cada archivo en el mismo orden y contra una base vacía:

```powershell
psql -v ON_ERROR_STOP=1 -d <base> -f database/01_tipos_dominios.sql
psql -v ON_ERROR_STOP=1 -d <base> -f database/02_tablas.sql
psql -v ON_ERROR_STOP=1 -d <base> -f database/03_restricciones.sql
psql -v ON_ERROR_STOP=1 -d <base> -f database/04_funciones.sql
psql -v ON_ERROR_STOP=1 -d <base> -f database/05_triggers.sql
psql -v ON_ERROR_STOP=1 -d <base> -f database/06_indices.sql
psql -v ON_ERROR_STOP=1 -d <base> -f database/07_vistas.sql
```

Los `CREATE TABLE IF NOT EXISTS` permiten repetir ciertos pasos, pero estos
archivos **no son un sistema de migraciones**: no alteran automáticamente una
instalación previa que tenga una estructura distinta. Probar primero en una
base nueva. `03_restricciones.sql` crea roles grupales sin contraseña; requiere
permisos administrativos. Asignar las cuentas de conexión reales a esos roles
por un procedimiento operativo separado; no se guardan credenciales aquí.

Para actualizar una instalación de fase B a B.2, sin reconstruirla, ejecutar
`psql -v ON_ERROR_STOP=1 -d <base> -f database/migracion_b2.sql` con una cuenta
autorizada como propietario. El script cambia una sola acción referencial y
reinstala los triggers dentro de una transacción con bloqueo exclusivo de las
cuatro tablas afectadas. Un error revierte todo; programar una ventana de
mantenimiento porque espera a las transacciones activas. Para una instalación
nueva bastan `01`–`07`; IF NOT EXISTS no migra una FK preexistente.

La instalación inicial `01`–`07` se ejecuta con una cuenta administrativa en
una base dedicada. Al terminar `07`, el esquema, tablas (con índices y
secuencias identity), vistas, tipos, dominio y rutinas pertenecen realmente a
`bodegas_propietario`. Los SECURITY DEFINER dejan de pertenecer al administrador.
El cierre de propiedad se ubica al final de `07` porque allí ya existen todos
los objetos; no agrega un script de instalación duplicado.

Para mantenimiento, una cuenta autorizada puede ejecutar `SET ROLE
bodegas_propietario` y reaplicar `02`–`07`, con `search_path` inicialmente en
`bodegas_atuel, public`. `01` es bootstrap administrativo: `CREATE SCHEMA`
requiere CREATE sobre la base incluso con IF NOT EXISTS. No se concede ese
permiso global al dueño para simular que GRANT equivale a propiedad. Crear roles
ausentes sigue siendo una tarea administrativa. Las cuentas API/reportes solo
reciben su rol correspondiente; nunca membresía del propietario.

Los defaults de EXECUTE se revocan para el creador y para el propietario en
toda esta base dedicada: un REVOKE limitado al esquema no elimina el permiso
global de PUBLIC. Los objetos existentes tienen además REVOKE/GRANT explícitos.
Véase [ALTER DEFAULT PRIVILEGES](https://www.postgresql.org/docs/18/sql-alterdefaultprivileges.html).
Reportes puede consultar las tres vistas y stocks/auditoría, sin escribir ni
ejecutar procedimientos de procesamiento. La API no tiene CREATE en el esquema,
DML de stocks/auditoría, ni UPDATE de totales; los triggers realizan esos cambios.

## Correspondencia y restricciones

`02_tablas.sql` crea las 29 relaciones del DBML. Declara PK simples/compuestas,
las 35 FK, `NOT NULL` y cuatro UNIQUE adicionales: parcela/campaña en Lote;
nombre/añada/presentación en Vino; tipo/número de documento en Cliente; y CUIT
en Transportista. El CUIT de Bodega ya es su PK y no se cuenta otra vez.
`01_tipos_dominios.sql` define los ENUM de estado/tipo y `dominio_cuit` de once
dígitos.

Las tres tablas de subtipos usan PK/FK compartidas. Triggers diferidos bloquean
el cierre de una transacción si el Cliente no pertenece exactamente al subtipo
que indica `tipo_cliente`. La escritura de subtipos bloquea la fila del
supertipo para evitar que operaciones concurrentes incorporen subtipos
incompatibles. Las composiciones de vino se validan al cierre transaccional:
debe existir al menos una cepa y la suma ser exactamente 100 %; el porcentaje
individual debe ser mayor que cero y menor o igual a 100.

`ck_cliente_nombre` exige `nombre` no nulo ni vacío después de quitar espacios.
Esa columna representa nombre personal o razón social; `apellido` sigue siendo
opcional y no se impone a empresas. No cambia la jerarquía ni las 29 relaciones.

La fecha de confección de transferencia se fija a `CURRENT_DATE`. Ingresos y
transferencias se crean en `en_confeccion`; sus únicas transiciones permitidas
son `en_confeccion → terminado → procesado`. Un detalle solo puede modificarse
mientras la cabecera está en confección.
Una cabecera procesada rechaza cualquier cambio efectivo, incluida sala,
bodega, transportista, fecha, clave o estado; un UPDATE que no cambia valores
no vuelve a aplicar stock.

## Funciones, procedimientos y triggers

Funciones de dominio y consulta:

- `fn_descuento_tipo(tipo_cliente)`: tasa inicial (10/20/30 %).
- `fn_descuento_cliente(id_cliente)`: descuento vigente almacenado.
- `fn_total_comprobante(numero_comprobante)`: total neto con precios
  históricos del detalle y tasa histórica de la cabecera.
- `fn_recalcular_totales_comprobantes()`: operación U1 aprobada; recalcula todos
  los comprobantes con `comprobante.descuento_aplicado`.
- `fn_stock_sala(id_sala, codigo_vino)` y `fn_antiguedad_anios(fecha)`.
- `fn_validar_composicion_vino(codigo)` y `fn_validar_cliente_isa(id)`: validan
  las restricciones diferidas de composición y de la ISA total/disjunta.

Procedimientos:

- `CALL sp_procesar_ingreso(codigo)`: procesa el ingreso terminado una sola vez.
- `CALL sp_procesar_transferencia(solicitud)`: procesa la transferencia
  terminada una sola vez.

Triggers principales:

- `tg_inicializar_descuento_cliente` asigna la tasa base y limita la tasa del
  35 % a exportadores elegibles; `tg_proteger_comprobante` fija el descuento
  histórico al emitir y protege la cabecera.
  En UPDATE rechaza un total distinto de `fn_total_comprobante`, incluso si
  escribe el propietario mediante DML. El mismo cálculo permite los recálculos
  legítimos de detalles y U1; asignar el valor correcto no es una evasión.
- `tg_movimiento_stock_venta` reintegra la cantidad anterior y descuenta la
  nueva mediante un UPDATE condicional atómico. Si falta stock, la operación
  completa falla. Bloquea primero las cabeceras afectadas en orden para
  serializar cambios concurrentes del mismo comprobante.
- `comprobante_vino` referencia su cabecera con `ON DELETE CASCADE`. El trigger
  de cabecera solo permite borrar una venta con renglones cuando cumple D1.
  Durante la cascada la cabecera ya no existe y el trigger de detalle no toca
  stock. Un DELETE directo de detalle encuentra su cabecera, reintegra botellas
  y recalcula el total como antes. La distinción depende de la FK y de la
  existencia real del padre, no de profundidad de triggers ni GUC.
- `tg_actualizar_total_comprobante` llama a
  `fn_recalcular_total_comprobante`, que bloquea la cabecera y recalcula con el
  descuento histórico.
- `tg_bloquear_composicion_vino`,
  `tg_validar_composicion_diferida` y
  `tg_comprobar_cliente_isa_diferido` coordinan las validaciones entre filas.
  `tg_guardar_tipo_subtipo_cliente` serializa los cambios de supertipo/subtipo.
- `tg_proteger_estado_documento` y `tg_validar_lineas_documento` protegen las
  transiciones y los detalles de ingresos/transferencias. Solo se pueden
  borrar cabeceras que sigan en confección y, exclusivamente para Ingreso,
  cabeceras procesadas que cumplan D5. Transferencias procesadas y documentos
  terminados siguen protegidos; el DELETE directo de detalle procesado falla.
- `tg_aplicar_ingreso` y `tg_aplicar_transferencia` actualizan existencias al
  pasar de terminado a procesado. Las filas se ordenan por vino para reducir
  deadlocks; el estado y los saldos se confirman juntos.
- `tg_vino_crear_stock_deposito` crea el saldo inicial y
  `tg_auditar_cambio_precio` registra solo cambios efectivos. La auditoría usa
  `session_user`, que refleja el rol PostgreSQL autenticado; no confía en GUCs.
  Si varias personas se conectan con una misma cuenta técnica, la auditoría
  identificará esa cuenta compartida, no a cada persona.

La validación diferida de composiciones valida una sola vez cada vino afectado
por evento. Las rutinas anteriores tienen responsabilidades separadas; no se
mantienen funciones auxiliares que solo activaban o desactivaban GUCs de sesión.

`comprobante.total` es un agregado derivado que queda materializado por decisión
aprobada. No se considera que el trigger demuestre 3FN: la redundancia
cabecera/detalle se documenta separadamente en `docs/normalizacion.md`.

## Reglas RN-01 a RN-15

| Regla | Mecanismo principal |
|---|---|
| RN-01 | `vino.precio > 0`; precio único en la fila de Vino para toda la red. |
| RN-02 | FK Sala–Localidad; el encargado regional se almacena una vez en Localidad. |
| RN-03 | FK obligatoria de Empleado a Sala. |
| RN-04 | FK de Parcela a una Cepa y UNIQUE de parcela/campaña en Lote. |
| RN-05 | CHECK de porcentaje y constraint trigger diferido que valida suma 100 %. |
| RN-06 | Trigger de descuento base por subtipo, rango y regla de elegibilidad del 35 % de U6. |
| RN-07 | Tabla de permisos y CHECK de vencimiento posterior a emisión. |
| RN-08 | Trigger recalculador; `total` no se carga manualmente. |
| RN-09 | CHECK de stock no negativo y débito condicional atómico antes del renglón de venta. |
| RN-10 | ENUM, transición protegida, detalle inmutable fuera de confección y procedimiento transaccional. |
| RN-11 | Igual que RN-10; fecha de confección inmutable; débito/crédito de stock atómicos. |
| RN-12 | Trigger bloquea DML directo de detalles fuera de confección. D5 es la excepción documental aprobada: la cascada quita detalles de la cabecera elegible ya eliminada. |
| RN-13 | Trigger AFTER UPDATE que registra solo cambios efectivos de precio. |
| RN-14 | FK RESTRICT impiden borrar Transportista, Bodega o Vino con movimientos asociados conservados. Las cascadas documentales no eliminan esos maestros. |
| RN-15 | CHECK de positividad, stock no negativo, graduación entre 5 y 20 y dominio CUIT. |

## Eliminación histórica D1/D5 — política aprobada en B.2

La consigna exige borrar documentos, pero no indica revertir existencias. Por
decisión expresa del proyecto, una purga histórica mantiene el stock actual:
no cancela la venta ni revierte físicamente el ingreso. No se agrega un estado
`cancelado` ni un mecanismo general para revertir movimientos procesados.

- **D1:** DELETE de cabecera con cliente Socio y fecha estrictamente anterior
  a `CURRENT_DATE - INTERVAL '5 years'`. El guard de cabecera comprueba Socio,
  bloquea su Cliente y permite la cascada; ningún detalle devuelve botellas.
  Una cabecera no elegible con renglones sigue bloqueada. Las cabeceras vacías
  conservan su eliminación ordinaria, y el filtro D1 no las selecciona si son
  recientes o de otros tipos.
- **D5:** DELETE de Ingreso en `procesado` con `fecha < CURRENT_DATE - 365`.
  La cascada borra detalles; los triggers de impacto solo actúan al cambiar
  estado a procesado, no en DELETE. El permiso de borrado de confección se
  conserva para la operación ordinaria; el filtro D5 no la incluye.

Las dos sentencias están en [`../consultas/delete.sql`](../consultas/delete.sql),
con controles y ROLLBACK para probar sin alterar el dataset. Reemplazar por
COMMIT solo al decidir ejecutar la eliminación definitiva. No hay procedimiento,
rol ni autorización por variable de sesión nuevos. Las FK siguen activas y
las filas afectadas se bloquean durante la transacción. Ante bloqueo mutuo o
serialización fallida se revierte y debe reintentarse la transacción completa;
no se omiten controles. La semántica de cascadas y triggers está documentada
en [PostgreSQL](https://www.postgresql.org/docs/18/trigger-definition.html).

La excepción documental D5 se distingue del DML directo prohibido por RN-12.
Esta es la interpretación aprobada del proyecto, no una aprobación docente
inventada; debe explicarse en la defensa junto al texto literal. La eliminación
es definitiva y borra trazabilidad: sin un respaldo previo, ya no se reconstruyen
ventas, totales ni saldos actuales solo con los documentos restantes. Los
reportes históricos excluyen documentos purgados; no se agregan tablas de archivo.

## U1 y descuentos

Al emitir una venta, el trigger copia `cliente.descuento` a
`comprobante.descuento_aplicado`. Ese porcentaje es histórico e inmutable; U6
solo cambia el valor vigente del Cliente. U1 se ejecuta mediante:

```sql
SELECT bodegas_atuel.fn_recalcular_totales_comprobantes();
```

La función usa:

```text
ROUND(SUM(cantidad * precio) * (1 - descuento_aplicado / 100), 2)
```

Los precios son los guardados en `comprobante_vino`; no se consulta el precio
actual de `vino`. El texto literal de U1 habla del descuento “que corresponde
al tipo de cliente”; si pretendiera la tasa vigente actual, diferiría de la
interpretación histórica aprobada. Esa discrepancia se conserva en
`docs/validacion_tpi.md`.

## Índices y vistas

`06_indices.sql` agrega índices de FK no cubiertas por el prefijo izquierdo de
una PK/UNIQUE, fechas de consulta/operación y búsquedas de auditoría. No duplica
los índices que PostgreSQL crea para claves primarias y restricciones UNIQUE.

`07_vistas.sql` crea:

- `vw_stock_total_vino`: stock de depósito más todas las salas.
- `vw_ventas_mensuales_sala`: totales mensuales por sala.
- `vw_documentos_pendientes`: ingresos y transferencias no procesados.

La provincia de Finca se recupera mediante JOIN a Localidad; no se agrega una
vista adicional.

## Pruebas y estado de validación

Después de instalar, ejecutar en una base **vacía de pruebas**:

```powershell
psql -v ON_ERROR_STOP=1 -d <base_prueba> -f database/08_pruebas_integridad.sql
psql -v ON_ERROR_STOP=1 -d <base_prueba> -f database/09_pruebas_reglas_negocio.sql
```

Ambos archivos crean fixtures dentro de una transacción y terminan con
`ROLLBACK`. Incluyen casos válidos/negativos para claves, dominio, composición,
ISA, las cuatro claves UNIQUE, descuentos históricos, totales, stock, borrado
de comprobantes y conservación de documentos procesados, estados, procesos de
ingreso y transferencia y auditoría de identidad. La prueba concurrente de varias
sesiones debe realizarse además en el servidor desplegado.

Las operaciones concurrentes de venta se apoyan en `UPDATE ... WHERE
cantidad_stock >= cantidad`: PostgreSQL bloquea la fila y comprueba la condición
con el saldo actualizado. Las operaciones de ingreso/transferencia procesan los
vinos en orden y el cambio de estado junto con los saldos pertenece a la misma
transacción.

## Resultado de validación y alcance

La fase B instala `01`–`07` en un clúster descartable PostgreSQL 18 y ejecuta las
suites `08`/`09`, con salidas conservadas en
[`../docs/evidencias/fase_b_postgresql.log`](../docs/evidencias/fase_b_postgresql.log).
La versión exacta, códigos de salida y verificación final constan en ese log.
Las pruebas verifican propiedad real, search_path, ACL de rutinas nuevas,
roles API/propietario/reportes mediante SET ROLE, ISA, identidad nominal,
descuentos históricos con venta no vacía, modificación manual de total,
cabeceras procesadas, venta sin stock y atomicidad multirrenglón. Cada suite
revierte sus fixtures. Una función de prueba se crea dentro de la transacción
para comprobar defaults de ACL; tampoco queda instalada.

La prueba concurrente relatada por la versión anterior del README es un
antecedente sin salida conservada, no evidencia de esta ejecución. No se
afirma compatibilidad probada en PostgreSQL 14 ni se realiza aquí despliegue,
carga masiva o medición de rendimiento. El propietario real puede ejecutar DDL
y desactivar controles; el alcance de la protección del total es DML autorizado
con los triggers activos, no impedir administración deliberada.

En B.2 las suites `08` y `09` pasan tanto en instalación nueva como sobre una
instalación de fase B actualizada con `migracion_b2.sql`. La suite compara las
tablas completas de stock antes/después de D1/D5, comprueba los límites exactos,
exclusiones y rollback tras ambas cascadas. Se ejecutó también el archivo de
consultas con datos elegibles y ROLLBACK. Dos sesiones READ COMMITTED intentaron
la misma purga por cada operación: una borró una cabecera y la otra cero; los
saldos finales siguieron en 15 botellas de sala y 80 de depósito. Evidencia:
[`fase_b2_postgresql.log`](../docs/evidencias/fase_b2_postgresql.log).

El TPI menciona el CUIT de Bodega como ejemplo de UNIQUE adicional, pero ya es
la PK de Bodega, por lo que no incrementa el conteo de constraints UNIQUE
adicionales. Para completar las cuatro se modelan las claves alternativas de
Vino, Lote, Cliente y Transportista descritas arriba. La unicidad del documento
por tipo y la del CUIT de Transportista se basan en que esos atributos
identifican a la persona/entidad; no se imponen unicidades a nombres, teléfonos
ni domicilios.

La implementación de U1 usa descuentos históricos según la decisión del
   proyecto; la posible discrepancia con el sentido literal del TPI está
anotada en `docs/validacion_tpi.md`.
