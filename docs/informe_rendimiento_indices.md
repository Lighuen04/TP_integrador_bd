# Índices y rendimiento — cierre de fase E

## Objetivo y resultado

Se completan los requisitos de etapa 4 sobre la carga original de fase C, sin
cambiar tablas, 3FN, reglas, descuentos ni inventario. La consigna local, etapa 4
(pp. 14–15), exige ≥5 índices con compuesto, parcial, FK y variante; comparación
con solo PK/UNIQUE; mejora medida en ≥3 consultas; costo de escritura y un descarte.
Los experimentos muestran tres mejoras claras: **S2, S3 y D4**. Se conservan también
los resultados negativos y los índices que el planificador no utiliza.

Evidencia completa: [fase_e_indices.json](evidencias/fase_e_indices.json), con
SQL, parámetros, siete tiempos, planificación, buffers, filas, sorts y un plan
JSON completo por consulta/escenario (el de ejecución mediana). No se duplican
los mismos planes en otros logs del repositorio. La auditoría de las 30 operaciones
y las regresiones I1/I3 están en [fase_d_consultas.json](evidencias/fase_d_consultas.json).

## Entorno y volumen

PostgreSQL 18.4 x64, Python 3.9.13/psycopg 3.2.13, Windows build 26200; CPU
Intel64 Family 6 Model 154 Stepping 4 (8 procesadores lógicos). RAM física no
verificada. Configuración sin cambios entre A/B: shared_buffers=128 MiB,
work_mem=4 MiB, effective_cache_size=4 GiB (es una estimación del planificador,
no RAM medida), random_page_cost=4, seq_page_cost=1, hasta dos trabajadores por
Gather, JIT y recorridos secuencial/indexado/bitmap habilitados. READ COMMITTED.

Base explícitamente descartable `bodegas_e_medicion`, restaurada desde el dump
de fase C, fecha de ejecución 2026-11-09. Las 29 tablas contienen **357.894 filas**:
100.001 comprobantes, 200.002 renglones, 20.000 clientes, 16.665 permisos,
120 lotes y 18 transferencias. Los conteos y huellas por tabla constan en el JSON.
Las bases de referencia A/B no se modifican.

## Metodología reproducible

1. Retirar únicamente secundarios de la copia: quedan 29 PK y cuatro UNIQUE
   (33 índices automáticos); no se deshabilitan FK ni triggers.
2. VACUUM (ANALYZE) en A/B para estadísticas y visibilidad comparables. Una
   ejecución de calentamiento excluida; siete ejecuciones medidas, con orden
   de consultas barajado de forma reproducible (semilla 42). Sin carga concurrente
   deliberada; no se modifican costos, enable_* ni límites de paralelismo.
3. Registrar EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON). Comparar medianas, rango
   mínimo/máximo y cambio de acceso, no solo aparición de Index Scan. Los planes
   representativos tuvieron Shared Read Blocks=0: es una comparación con caché
   caliente, no un ensayo de disco frío ni capacidad de producción.
4. Crear los índices definitivos con `06_indices.sql` sobre las mismas filas,
   volver a analizar y repetir. D4 se ejecuta realmente dentro de transacción
   con constraints inmediatas y ROLLBACK en cada muestra, incluyendo su costo
   de integridad en ambos escenarios.
5. Medir escritura con muestra equivalente y rollback; verificar finalmente las
   29 huellas, las FK y los 26 controles del validador de carga. Todos pasaron.

Para reproducir, restaurar el dump en otra base `bodegas_e_*` según
[la guía de carga](../database/seed/README.md#dump-comprimido). El runner no crea
ni limpia bases: **elimina y reconstruye secundarios solo de la copia identificada**.
Usa las dependencias ya existentes de `database/seed/requirements.txt`.

```powershell
$env:PGHOST = '127.0.0.1'
$env:PGPORT = '55441'
$env:PGUSER = '<cuenta con membresía de propietario>'
$env:PGDATABASE = 'bodegas_e_medicion'
.\.venv\Scripts\python.exe -X utf8 database/benchmark/medir_indices.py --base-prueba bodegas_e_medicion --salida docs/evidencias/fase_e_indices.json
```

Los parámetros salen de los SQL entregados: S3 sala 1, S4 vino V001, S5 todas
las salas, S8 trimestre móvil, S2 todas las salas/vinos; D4 socios sin compras
con alta de más de cinco años. Los límites temporales se conservan con CURRENT_DATE.
No se sustituyen consultas por versiones más selectivas para simular mejoras.

## índices elegidos y conservados

De los 23 secundarios originales, **21 conservan nombre y definición**. Dos
se sustituyen por otros que cubren sus prefijos; se agrega un parcial: total
**24 secundarios**, además de los 33 automáticos. Ocupan conjuntamente 13,52 MiB
al finalizar la prueba. No se duplican los índices automáticos de claves.

- `ix_comprobante_sala_fecha` → `ix_comprobante_sala_fecha_cubriente`:
  `(id_sala,fecha) INCLUDE(id_cliente)`. S3 usa igualdad antes del rango;
  devuelve 1.230 de 100.001 comprobantes (1,23 %). INCLUDE evita obtener el
  cliente desde el heap; el plan medido hace cero Heap Fetches.
- `ix_comprobante_vino_codigo_vino` → `ix_comprobante_vino_venta`:
  `(codigo_vino,numero_comprobante)`. S2 filtra por vino y puede recorrer sus
  comprobantes ordenados. La PK tiene el orden contrario. No se incluye cantidad:
  esa columna no es necesaria para S2 y el candidato para S1 no fue elegido.
- Nuevo `ix_transferencia_pendientes`: `(id_sala) WHERE estado <> 'procesado'`.
  Su predicado coincide exactamente con S5. **Con 18 filas no se usa ni se
  demuestra aceleración**: se mantiene para el requisito explícito de índice
  parcial, asociado a una consulta real, con costo medido de solo 16 KiB.
  No se presenta como una necesidad productiva demostrada ni como mejora futura
  garantizada. El índice completo por sala/fecha sigue cubriendo historial y FK.

Los cinco mínimos se justifican concretamente por los dos primeros, el parcial,
`ix_comprobante_cliente_fecha` (D4/FK) e `ix_permiso_id_exportador` (U6 y COUNT del
trigger). El plan de ese COUNT usa el índice; los compuestos y la variante INCLUDE
no son categorías inventadas por cantidad. Los demás índices se conservan por
sus accesos y controles referenciales existentes; **no se afirma una mejora
medida individual de los índices de tablas pequeñas** ni se indexan nuevas FK
indiscriminadamente.

| índice definitivo | Tamaño | Acceso / motivo |
|---|---:|---|
| `ix_analisis_numero_lote_fecha` | 16 KiB | Análisis de un lote ordenados por fecha; FK a Lote. |
| `ix_auditoria_vino_fecha` | 16 KiB | Historial RN-13 por vino, fecha y hora descendentes. |
| `ix_cliente_codigo_postal` | 152 KiB | D6 y FK de Cliente a Localidad. |
| `ix_composicion_id_cepa` | 16 KiB | D2 y FK de composición a Cepa (la PK empieza por vino). |
| `ix_comprobante_cliente_fecha` | 2328 KiB | D4/D6: FK a Cliente; igualdad de cliente primero, fecha después. |
| `ix_comprobante_fecha` | 816 KiB | D1/control de comprobantes antiguos; no acelera S8 al seleccionar 95 %. |
| `ix_comprobante_sala_fecha_cubriente` | 3584 KiB | S3: igualdad de sala, rango de fechas e INCLUDE de cliente. |
| `ix_comprobante_vino_venta` | 6416 KiB | S2: vino primero y comprobante después; conserva soporte de FK a Vino. |
| `ix_empleado_id_sala` | 16 KiB | D3 y FK de Empleado a Sala. |
| `ix_finca_codigo_postal` | 16 KiB | FK de Finca a Localidad. |
| `ix_ingreso_bodega` | 16 KiB | FK de Ingreso a Bodega. |
| `ix_ingreso_transportista_fecha` | 16 KiB | I1/S7 y FK a Transportista. |
| `ix_ingreso_vino_codigo_vino` | 16 KiB | FK de detalle de Ingreso a Vino. |
| `ix_lote_bodega_destino` | 16 KiB | FK de Lote a Bodega y trazabilidad productiva. |
| `ix_parcela_id_cepa` | 16 KiB | D2, existencia de parcelas por cepa y FK. |
| `ix_permiso_id_exportador` | 256 KiB | U6, COUNT de permisos del trigger y FK a Exportador. |
| `ix_sala_venta_codigo_postal` | 16 KiB | FK de Sala a Localidad; búsquedas/controles referenciales por localidad. |
| `ix_stock_sala_codigo_vino` | 16 KiB | S9/vista de stock y FK a Vino; la PK empieza por sala. |
| `ix_transferencia_pendientes` | 16 KiB | S5: predicado estado <> procesado; seis de dieciocho cabeceras. |
| `ix_transferencia_sala_fecha` | 16 KiB | FK a Sala y acceso sala/fecha también de procesados; no equivale al parcial. |
| `ix_transferencia_vino_codigo_vino` | 16 KiB | S4 y FK de detalle de Transferencia a Vino. |
| `ix_transportista_localidad_codigo_postal` | 16 KiB | FK a Localidad en cobertura; la PK empieza por transportista. |
| `ix_vino_cuit_bodega` | 16 KiB | U3/S12 y FK de Vino a Bodega. |
| `ix_vino_maridaje_id_maridaje` | 16 KiB | FK a Maridaje (la PK empieza por vino). |

## Comparación antes/después

Tiempos en milisegundos. Δ=B−A; porcentaje positivo indica reducción de mediana.
Los rangos completos y tiempos de planificación se conservan en la evidencia.
S11_1 es ranking; S11_2 es acumulado mensual. D4 devuelve 333 IDs y los revierte.

| Consulta | A: PK/UNIQUE | B: secundarios | → ms | Reducción | Recorridos A → B | índice secundario elegido | Conclusión |
|---|---:|---:|---:|---:|---|---|---|
| S1 | 122,273 | 117,503 | -4,770 | 3.90 % | Seq Scan → Seq Scan | `ninguno secundario` | Sin mejora atribuible: mismo acceso, rangos solapados. |
| S2 | 117,135 | 10,686 | -106,449 | 90.88 % | Index Only Scan/Index Scan/Seq Scan → Index Only Scan/Index Scan/Seq Scan | `comprobante_pkey, ix_comprobante_vino_venta` | Mejora clara del acceso por vino/comprobante. |
| S3 | 25,444 | 6,235 | -19,209 | 75.50 % | Function Scan/Seq Scan → Function Scan/Index Only Scan/Seq Scan | `ix_comprobante_sala_fecha_cubriente` | Mejora clara: lectura cubierta de compradores. |
| S4 | 0,108 | 0,169 | 0,061 | -56.48 % | Seq Scan → Seq Scan | `ninguno secundario` | Empeora la mediana; submilisegundo y rangos solapados. |
| S5 | 0,120 | 0,108 | -0,012 | 10.00 % | CTE Scan/Seq Scan → CTE Scan/Seq Scan | `ninguno secundario` | No se atribuye mejora: parcial ignorado, tabla mínima. |
| S8 | 116,887 | 115,204 | -1,683 | 1.44 % | Seq Scan → Seq Scan | `ninguno secundario` | Sin mejora atribuible: mismo acceso, rangos solapados. |
| S10 | 4,777 | 4,680 | -0,097 | 2.03 % | CTE Scan/Seq Scan → CTE Scan/Seq Scan | `ninguno secundario` | Sin mejora atribuible: mismo acceso, rangos solapados. |
| S11_1 | 181,568 | 173,274 | -8,294 | 4.57 % | Seq Scan/Subquery Scan → Seq Scan/Subquery Scan | `ninguno secundario` | Sin mejora atribuible: mismo acceso, rangos solapados. |
| S11_2 | 143,821 | 136,092 | -7,729 | 5.37 % | Seq Scan/Subquery Scan → Seq Scan/Subquery Scan | `ninguno secundario` | Sin mejora atribuible: mismo acceso, rangos solapados. |
| D4 | 4688,286 | 129,623 | -4558,663 | 97.24 % | Seq Scan → Seq Scan | `ix_comprobante_cliente_fecha (FK interna)` | Mejora clara en comprobación interna de FK. |

Las tres mejoras claras tienen rangos sin solapamiento en esta corrida:
S2: 92,506–137,040 → 9,587–15,119 ms; S3: 20,457≥32,595 → 5,904–9,270 ms;
D4: 3951,994≥5511,258 → 105,037–187,722 ms. No se cuentan como mejoras demostradas
las pequeñas diferencias con igual plan y rangos superpuestos de los demás casos.
S4 empeora su mediana en 0,061 ms; se informa sin atribuir causalidad a índices
que no aparecen en su plan.

## Lectura de planes

- **S2:** el detalle pasa de usar su PK en orden comprobante/vino a Index Only
  Scan del índice en orden vino/comprobante. Los shared hits bajan de 4.551 a
  1.461, sin tocar las reglas de división ni las 36 filas del resultado.
  Ambos accesos son Index Only Scan: la mejora está en el orden de claves y
  las páginas visitadas, no en cambiar el nombre del tipo de recorrido.
- **S3:** Seq Scan de 100.001 cabeceras, descartando 98.771, pasa a Index Only
  Scan de las 1.230 calificadas; shared hits totales bajan de 1.045 a 312.
  El recorrido de Cliente permanece secuencial para el join, no se fuerza otro.
- **D4:** el plan principal no muestra el índice utilizado por las comprobaciones
  internas de FK. El trigger `fk_comprobante_cliente` hace 333 llamadas y baja
  de 4455,227 a 8,189 ms en los planes representativos. Un ensayo adicional
  confirma un incremento de **335 idx_scan** del índice de cliente al ejecutar
  D4 y revertirlo. Por eso no se interpreta el listado vacío de índices del
  plan principal como ausencia de uso. Los totales de buffers del nodo principal
  tampoco sustituyen esa evidencia de triggers.
- **S1/S8/S11:** reportes amplios mantienen recorridos secuenciales, joins,
  agregaciones y ordenamientos. S8 lee 95.001 de 100.001 cabeceras (95 %);
  un índice por fecha no evita procesar la mayor parte de la tabla. Es el caso
  observado de un índice existente que el planificador ignora.
  S1 usa top-N heapsort de 26 KiB; S11 ordena 216 rankings en 33 KiB y 48 meses
  en 26 KiB mediante quicksort. Esos sorts permanecen en memoria, sin lecturas
  temporales: no se inventa un problema de disco para justificar más índices.
- **S4/S5/S10:** 18 transferencias o 120 lotes no justifican afirmar ventajas
  de milisegundos a partir de unas pocas páginas. S5 filtra seis pendientes y
  descarta doce procesados mediante Seq Scan; el parcial no se eligió.

Los planes JSON incluyen Actual Rows/Loops, filas descartadas, buffers, workers,
Sort Method/espacio usado y tiempos de planificación. Sus filas son salidas de
cada nodo, no «filas únicas leídas»: no se suman padres e hijos como si fueran
registros distintos. La instrumentación mide tiempo servidor, no renderizado
ni transferencia completa de los resultados.

## Candidato descartado

Se creó y midió `BRIN(fecha)` sobre Comprobante junto a los índices B. Mismo
S8, una ejecución de calentamiento y siete muestras: mediana **115,536 ms**, frente
al B original **115,204 ms**. El plan siguió Seq Scan y no utilizó BRIN. El candidato
ocupó 24 KiB; correlación fecha/orden físico 0,15375309. El trimestre selecciona
95 % de la tabla y las fechas recientes están dispersas: no hay ventaja observada
que compense otra estructura y su mantenimiento. Se eliminó el BRIN del experimento
y no se incluyó en `06_indices.sql`. La mínima diferencia de tiempo no prueba
que BRIN ralentice esa consulta: está dentro de la variación observada.

La exploración también rechazó cubrir S1 solo con vino/cantidad y cubrir S8 con
fecha/total: el planificador no los eligió. No se publicitan sus tiempos exploratorios
como mejoras; la selección definitiva se volvió a medir desde la base sin secundarios.

## Costo de escritura

Misma tabla de 200.002 renglones, 2.000 INSERT nuevos válidos por muestra; stock
aprovisionado y cabeceras creadas por mecanismos normales antes del tiempo medido.
Triggers y FK activos en A/B; cinco muestras por método tras calentamiento.
Misma limpieza VACUUM (ANALYZE) antes de cada muestra, y ROLLBACK del ensayo.
Se mide la inserción de renglones y sus efectos automáticos, no la carga completa.

| Método | A mediana s | B mediana s | Incremento observado | Rango A s | Rango B s |
|---|---:|---:|---:|---:|---:|
| fila | 1,471 | 2,154 | +46.43 % | 1,429–1,829 | 1,510–2,281 |
| copy | 1,030 | 1,527 | +48.25 % | 0,906–1,126 | 0,881–1,675 |

Los rangos de escritura se solapan y A se midió antes de B: las medianas describen
esta corrida, no una estimación universal ni una penalización causal exacta del
46–48 %. La conclusión prudente es que mantener secundarios tiene costo y debe
presupuestarse, sin extrapolar esos porcentajes al generador entero ni a producción.
Los beneficios de lectura de S2/S3/D4 son mucho más claros que la magnitud exacta
del costo de escritura. El archivo incluye todas las muestras, no solo la mejor.

## Auditoría final de consultas y cierre

Se reejecutaron los cuatro archivos: **30/30 operaciones**, todos con código 0;
se conservaron las 29 huellas tras ROLLBACK. I1 conserva la selección de mínimo
global y desempate determinista: si el ganador ya cubre General Alvear, cero
inserciones es idempotencia válida, no una selección alternativa de mayor actividad.
Se probó el caso de T4 ya cubierto y único mínimo frente a T1/T2/T3 más activos.

I3 tuvo una corrección mínima de consulta, no del esquema: el INSERT SELECT
anterior omitía un vino inexistente y podía generar solo dos renglones. Ahora
VALUES conserva los tres pedidos con LEFT JOIN de precios; si falta uno,
los controles existentes rechazan la venta (en la prueba actuó primero el
trigger de stock, SQLSTATE 23514; NOT NULL/FK permanecen activos). Se reprodujo
el defecto previo (dos renglones),
y se verificó el rechazo actual, el rechazo por stock insuficiente, tres precios
históricos válidos, descuento 10 %, total 3.267,00 y rollback de cabecera/stock.
No se agregaron funciones ni validaciones duplicadas del esquema.

**Etapa 4 completa:** hay ≥5 índices, compuesto, FK, parcial e INCLUDE; tres
mejoras claras con los mismos datos; planes completos; costo de escritura;
BRIN descartado e índices ignorados explicados. La salvedad es explícita: el
parcial satisface el requisito y el patrón S5, pero con esta carga pequeña no
acelera la consulta. No se modifica el dataset para fabricar ese beneficio.
Las reglas RN-01–RN-15 y las políticas históricas permanecen; los 26 controles
finales pasan. Quedan otras etapas (API/front/despliegue), diccionario y demo
académica de concurrencia, no bloqueos de las 30 operaciones ni de este experimento.

Referencias técnicas primarias: [EXPLAIN](https://www.postgresql.org/docs/18/using-explain.html),
[índices parciales](https://www.postgresql.org/docs/18/indexes-partial.html) e
[Index Only Scan/INCLUDE](https://www.postgresql.org/docs/18/indexes-index-only-scans.html).
La visibilidad del heap también condiciona Index Only Scan; de ahí el tratamiento
igual de VACUUM en A/B, no una promesa de cero visitas al heap tras cualquier escritura.
