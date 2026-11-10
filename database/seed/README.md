# Carga reproducible — Etapa 3

Para Docker Compose, la fase H reutiliza este mismo generador mediante
`scripts/operar_docker.py cargar`, en una imagen de herramientas definida por
`database/seed/Dockerfile`. No publica PostgreSQL al host ni instala Faker en
la API. La base inicial vacía se conserva; se crea una base nueva identificada
`bodegas_c_docker_*` y solo después de validar se activa en la aplicación.
Los comandos probados, las precauciones con datos existentes y la restauración
están en el [README principal](../../README.md#herramientas-y-carga-masiva).

Ejecutar desde la raíz, después de instalar los SQL `01`–`07` vigentes (o migrar
una instalación B con `migracion_b2.sql`). No usar una base con datos reales.
El generador no crea tablas, no ejecuta DROP/TRUNCATE y rechaza cualquier tabla
no vacía. La base debe identificarse expresamente y llamarse `bodegas_c_*`.

## Ejecución

Python 3.9 o superior. Únicas dependencias directas: psycopg 3.2.13 con binario
y Faker 37.12.0; se fijan versiones para repetir los nombres ficticios.

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r database/seed/requirements.txt
$env:PGHOST = '127.0.0.1'
$env:PGPORT = '5432'                 # 55441 en el clúster local de esta prueba
$env:PGDATABASE = 'bodegas_c_a'
$env:PGUSER = '<cuenta autorizada>'
# PGPASSWORD, si se necesita, se configura fuera del repositorio.
New-Item -ItemType Directory -Force .local | Out-Null
.\.venv\Scripts\python.exe -X utf8 database/seed/generar_datos.py --base-prueba bodegas_c_a --seed 42 --fecha-ref 2026-11-09 --reporte .local/carga_a.json
```

Crear el directorio de salida antes de usar `--reporte`, o omitir esa opción
para obtener JSON por stdout. La conexión usa las variables estándar de libpq;
el script cambia a `bodegas_propietario`, por lo que la cuenta debe tener esa
membresía. Nunca necesita ser la cuenta de la futura API. La fecha debe ser
explícita, no futura y distinta del 29 de febrero; semilla predeterminada 42.
Para repetir, crear **otra base de prueba vacía**, instalar `01`–`07` y cambiar
PGDATABASE/`--base-prueba`. No hay reinicialización destructiva automática.

Validación independiente con la misma fecha de referencia:

```powershell
psql -X -v ON_ERROR_STOP=1 -v fecha_ref=2026-11-09 -f database/seed/validar_carga.sql
```

El SQL muestra controles y estados, informa conteos y falla con una excepción
si algún control, FK, PK/UNIQUE o mínimo de volumen no se cumple. Sus consultas
de historia/precios/descuentos son específicas del perfil de este generador.
No ejecutarlas como si fueran un validador universal de cualquier dataset.

## Datos y orden de carga

Se leen cinco CSV: cepas, maridajes, departamentos, localidades y tipos de vino.
Cepas, maridajes, departamentos y tipos provienen del anexo B de la consigna;
se incluye un subconjunto real de localidades mendocinas con código postal.
Los CSV se consumen como catálogos, sin agregar tablas para departamentos o
tipos. Personas, empresas, CUIT de once dígitos y direcciones son ficticios;
los CUIT cumplen el dominio del esquema, sin afirmar validación fiscal.

Orden: localidades/cepas/maridajes → salas/empleados/fincas/parcelas →
bodegas/lotes/análisis → vinos/composición/maridajes → clientes/subtipos/permisos
→ transportistas/coberturas → cabeceras históricas de transferencia →
ingresos y procesamiento → detalles de transferencias y procesamiento →
ventas antiguas → cambio de precio y descuento vigente → ventas recientes.
Los estados siempre pasan por confección, terminado y procesado usando los
procedimientos normales. Se conservan transferencias pendientes en ambos estados.

La composición y la ISA se cargan con sus constraints diferidas, y se fuerzan
antes de las ventas masivas. Los comprobantes se escriben en lotes de 1.000,
con dos renglones distintos cada uno. Hay 20.000 clientes y al menos 100.001
comprobantes (configurable con `--comprobantes`), sin guardar el historial completo
en memoria. La primera pasada suma demanda por sala/vino; la segunda genera
exactamente las mismas ventas para insertar. Cada sala recibe esa demanda más
un margen, salvo un par que termina en cero. El depósito recibe esas transferencias
más una reserva; los saldos solo los escriben los triggers. No se purga historia
durante la carga: permite conciliar todo el inventario desde sus documentos.

Las primeras 5.000 ventas son antiguas, con tasas base y precios históricos.
Antes del resto, algunos exportadores elegibles pasan al 35 % y se actualizan
los precios. Otros exportadores con cuatro permisos conservan 30 % para probar
U6. No se recalculan comprobantes previos. La auditoría se genera por el trigger
real de precios, no mediante INSERT artificial de eventos.

El conjunto incluye sala 1, General Alvear, Malbec Reserva de 750 ml, tintos
de más de 14°, vinos sin ventas, cepas sin uso, socios antiguos sin compras,
empleados nuevos/antiguos, variedades de rendimiento y un vino vendido en todas
las salas. Hay ventas recientes, pendientes y movimientos antiguos para D1/D5.
Los períodos de las consultas definitivas deben seguir usando CURRENT_DATE:
si se reutiliza el dataset mucho después de su fecha de referencia, los resultados
de «última semana» dejan de representar esa demostración y se debe regenerar.

## Importación histórica y reproducibilidad

RN-11 impone CURRENT_DATE al crear una transferencia operativa. No es posible
insertar por esa ruta transferencias anteriores a ventas antiguas. La carga hace
una importación histórica explícita: en la transacción y bajo bloqueo exclusivo,
suspende **solo `trg_transferencia_estado` durante el COPY de 18 cabeceras**.
Cada fila tiene fecha determinada por la referencia, estado en_confeccion y
referencias válidas. Se reactiva inmediatamente, antes de cargar detalles o
procesar. Los triggers de detalle, saldos, totales, composición e ISA y todas
las FK/CHECK permanecen activos. No se altera la definición de ninguna regla
ni se usa GUC de bypass. Un fallo revierte datos y ALTER TABLE conjuntamente.
Es un importador administrativo de historia en bases de prueba, no una nueva
ruta operativa autorizada a la API. El perfil valida fechas, estados y saldos
diarios históricos, además de comprobar que todos los triggers terminan activos.

La fecha de referencia controla todos los datos de negocio. El reloj real del
trigger RN-13 sigue registrando cuándo y con qué cuenta se ejecutó la carga.
Por eso la huella lógica excluye únicamente fecha/hora/usuario de auditoría:
no se falsifican esos metadatos. Incluye ID, vino, precio anterior/nuevo y todas
las columnas de las otras 28 tablas, ordenadas por sus PK. Una identity vacía
se reinicia transaccionalmente para no depender de pruebas previas con ROLLBACK.
Las huellas por tabla y la huella global aparecen en el reporte JSON. Dos bases
equivalentes, con las mismas versiones, semilla y fecha deben coincidir.

## Comparación de inserción

Con la carga terminada:

```powershell
.\.venv\Scripts\python.exe -X utf8 database/seed/generar_datos.py --base-prueba bodegas_c_a --fecha-ref 2026-11-09 --benchmark --reporte .local/benchmark_c.json
```

Compara 2.000 renglones equivalentes: una llamada INSERT por fila frente a COPY,
con los mismos índices y triggers activos. Antes de cada método aprovisiona
stock y crea las mismas cabeceras fuera del tiempo medido. Verifica sus totales
y termina cada caso con ROLLBACK. La huella completa de negocio antes/después
debe coincidir. Se mide esta muestra de ventas, no una mejora de índices ni
una garantía de aceleración idéntica para toda la carga.

## Dump comprimido

No versionar datos masivos. Usando las mismas variables PG*:

```powershell
pg_dump -Fp -f .local/dump_completo.sql
python -c "import gzip,shutil; src=open('.local/dump_completo.sql','rb'); dst=gzip.open('.local/dump_completo.sql.gz','wb'); shutil.copyfileobj(src,dst); dst.close(); src.close()"
```

Para restaurar en otra base de prueba, provisionar los tres roles NOLOGIN de
`03` administrativamente antes del dump (pg_dump no incluye roles globales),
descomprimir y ejecutar el SQL con psql como administrador. No instalar además
`01`–`07` sobre el mismo esquema restaurado. Ejecutar de nuevo el validador y
comparar conteos/huellas. La restauración del dump es un entregable distinto
de comparar dos cargas generadas; no confundir ambas evidencias.

## Resultados medidos

Ejecutados el 9/11/2026, semilla 42, referencia 2026-11-09, Python 3.9.13 y
PostgreSQL 18.4 en Windows. Evidencia: [fase_c_resultados.json](../../docs/evidencias/fase_c_resultados.json).

| Tabla | Filas reales |
|---|---:|
| analisis_calidad | 240 |
| auditoria_precios | 40 |
| bodega | 4 |
| cepa | 12 |
| cliente | 20.000 |
| composicion_vino_cepa | 60 |
| comprobante | 100.001 |
| comprobante_vino | 200.002 |
| distribuidor | 6.667 |
| empleado | 18 |
| exportador | 6.666 |
| finca | 6 |
| ingreso | 8 |
| ingreso_vino | 80 |
| localidad | 3 |
| lote_uva | 120 |
| maridaje | 8 |
| parcela | 24 |
| permiso_exportacion | 16.665 |
| sala_venta | 6 |
| socio | 6.667 |
| stock_deposito | 40 |
| stock_sala | 216 |
| transferencia | 18 |
| transferencia_vino | 228 |
| transportista | 4 |
| transportista_localidad | 11 |
| vino | 40 |
| vino_maridaje | 40 |

Total: **357.894 filas**; las 29 tablas pobladas, cuatro >10.000 y dos >100.000.
Generación+carga+validación: **146,193 s** en A y **113,259 s** en B. Se ejecutaron
concurrentemente en el mismo clúster; A también tenía intentos previos revertidos.
Estos tiempos son observaciones de ejecución, no una comparación de estrategias.
Las 29 huellas lógicas coincidieron, con huella global
`867f36e936c7e84bb9349f3603bf48a5fbb6b10c382a2aa07b37bf49b84e4a71`.

Los 26 controles dieron cero errores, y se verificaron las 35 FK y PK/UNIQUE.
La conciliación actual y los saldos diarios históricos de sala/depósito fueron
correctos. Se comprobó con una falla de FK durante importación que el rollback
restaura también el trigger suspendido, y que RN-11 operativa sigue forzando la
fecha actual e impidiendo editarla. El generador rechazó base no coincidente
y base ya poblada sin alterar sus huellas.

Benchmark con triggers activos sobre 2.000 renglones, sin otra carga concurrente:
INSERT por fila **1,303 s**; COPY **0,488 s** (aproximadamente 2,67 veces en esa
muestra). Ambos casos revirtieron sus datos y conservaron las huellas iniciales.
No se extrapola esa relación a otros servidores ni a todas las etapas de carga.

Se generó `.local/dump_completo.sql.gz` (**2.130.104 bytes**) y se restauró en
`bodegas_c_restaurada`, con validación aprobada y las 29 huellas iguales a B.
Los metadatos reales de auditoría y la importación histórica acotada son las
limitaciones expresas de la reproducibilidad descritas arriba. Aún no se han
implementado las consultas definitivas, API, frontend ni optimización de índices.

Las bases A/B y restaurada quedan guardadas en el clúster local de pruebas
`.local/postgres_c` (excluido de Git), iniciado en el puerto 55441. Para volver a iniciarlo desde
la raíz si está detenido, con los binarios PostgreSQL 18 disponibles:

```powershell
& 'C:\Program Files\PostgreSQL\18\bin\pg_ctl.exe' -D '.local\postgres_c' -l '.local\postgres_c.log' -o '-h 127.0.0.1 -p 55441' -w start
```

El clúster de prueba acepta conexiones locales como `postgres` sin contraseña;
no es la configuración de despliegue ni se abre a otras interfaces. El generador
no depende de esa cuenta ni de ese puerto: en otro entorno usa su cuenta con
membresía del propietario y sus variables PG*.

Para detener este clúster local, sin borrar sus datos:

```powershell
& 'C:\Program Files\PostgreSQL\18\bin\pg_ctl.exe' -D '.local\postgres_c' -m fast -w stop
```
