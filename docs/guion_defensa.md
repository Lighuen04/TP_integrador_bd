# Defensa técnica — Bodegas del Atuel

Integrantes confirmados: **Amigo L.** y **Perez M.**. Comisión y docente no
confirmados; no asignar aportes por alias Git. El guion prepara una exposición
de **14 minutos**. Cada integrante debe poder ejecutar cualquier bloque.

**Estado:** ensayo técnico local disponible. No hay URL pública verificada;
no presentar localhost, la CA privada del laboratorio ni una captura como nube.
Usar una copia nueva `bodegas_h_pruebas_*` para escribir; conservar la base activa.

## Preparación antes de entrar

1. `docker compose ps`: base/API saludables y frontend activo en 8081.
2. Abrir [matriz de cumplimiento](matriz_cumplimiento_tpi.md), DER, normalización,
   informe E y Swagger. La nómina debe cumplir §2.1 o contar con excepción real.
3. Crear un respaldo y restaurarlo con un nombre **nuevo**. No usar un archivo
   ni una base ya existentes para volver a ejecutar el comando.

```powershell
.venv/Scripts/python.exe scripts/operar_docker.py backup --archivo .local/backups/defensa.dump
.venv/Scripts/python.exe scripts/operar_docker.py restaurar --base bodegas_h_pruebas_defensa --archivo .local/backups/defensa.dump
.venv/Scripts/python.exe scripts/operar_docker.py validar --base bodegas_h_pruebas_defensa
```

Para ensayar la cadena completa sin cambiar la aplicación activa:

```powershell
$env:UI_BROWSER_CHANNEL='msedge'
.venv/Scripts/python.exe scripts/probar_concurrencia.py --base bodegas_h_pruebas_defensa --reporte .local/defensa/concurrencia.json
.venv/Scripts/python.exe scripts/probar_integracion_docker.py --base bodegas_h_pruebas_defensa --reporte .local/defensa/integracion.json
```

El segundo script abre Edge sin ventana contra contenedores temporales y conserva
capturas en la carpeta del reporte. Para una exposición manual en pantalla, el
operador puede activar **su copia de defensa** con `operar_docker.py activar
--base bodegas_h_pruebas_defensa` y después regresar a `bodegas_c_docker_demo`.
La selección es explícita: no escribir ejemplos sobre la referencia por accidente.
Las escrituras del script ya ejecutadas tienen prefijos H; para el recorrido
manual usar otros identificadores nuevos, por ejemplo `DEF-VENTA-01`.

## Recorrido de 14 minutos

| Tiempo | Qué mostrar / comando o pantalla | Resultado esperado | Concepto y explicación |
|---|---|---|---|
| 0:00–1:00 | Problema, esquema de tres servicios y catálogo | Datos de vinos reales de prueba y conexión saludable | La API/front demuestran la base; no reemplazan su integridad |
| 1:00–2:30 | DER y DBML: Parcela, Vino–Cepa, Cliente ISA | PK compuesta de parcela y asociaciones; un subtipo por cliente | Entidad débil, N:M con atributos y especialización total/disjunta. Señalar límites visuales aún pendientes del DER |
| 2:30–3:30 | `normalizacion.md`, descuento de comprobante | DF `numero_comprobante → descuento_aplicado`; tasa fuera del detalle | Se elimina una dependencia parcial. El total materializado es redundancia agregada, no una prueba de 3FN por trigger |
| 3:30–4:30 | Gestión: nuevo `DEF-CORTE80`, composición 80 % | Error «sumar 100» y vino ausente después | Trigger diferido valida al COMMIT. No rechaza Python por sumar 80; revierte vino, composición y saldo inicial |
| 4:30–6:00 | Nueva venta: cliente 1, sala 1, V001×1, número nuevo | Comprobante con precio histórico, descuento y total del backend | PostgreSQL captura precio/tasa, descuenta y calcula dentro de una transacción. En el perfil original cliente 1/V001 produce 1039,50 |
| 6:00–7:00 | Venta negativa identificada: vino H-ULTIMA en la copia preparada | Stock insuficiente; sin cabecera ni renglón parcial | La prueba de concurrencia dejó saldo cero. El error real es 23514→422, no toda respuesta 422 proviene de Pydantic |
| 7:00–8:00 | Transferencia nueva, sala 1, V001×1 → terminar → procesar | Estado procesado; saldo depósito baja y sala sube | Procedimiento llama a los triggers de estado/stock; repetir procesamiento se rechaza, no se actualiza stock desde JavaScript |
| 8:00–9:30 | Informe E, S3 y `EXPLAIN (ANALYZE,BUFFERS)` en copia | Cambio medido de acceso, buffers y tiempos del experimento | Índice `(id_sala,fecha) INCLUDE(id_cliente)`; igualdad primero, rango después. No atribuir velocidad al parcial ignorado |
| 9:30–11:00 | Ejecutar/abrir resultado de `probar_concurrencia.py` | PIDs distintos, 1 COMMIT, 1 ROLLBACK, stock 0, una cabecera | READ COMMITTED + UPDATE condicional revalida saldo tras esperar. Comparación sin/con FOR UPDATE solo en tabla didáctica aislada |
| 11:00–12:00 | Dump y `restauracion_validada` | 29 conteos/huellas y 26 controles iguales | Un backup solo está comprobado después de restaurar; rol global/secretos no se incluyen en pg_dump por base |
| 12:00–13:00 | Seguridad y TLS I | API sin DDL/stock directo; TLS 1.3; CA y nombre incorrectos rechazados | Cifrar no es verificar identidad. verify-full exige CA y SAN correcto. La CA local no prueba confianza pública |
| 13:00–14:00 | Matriz y estado de nube | Separación explícita entre local probado y nube pendiente | Sin VM/dominio/autorización no hay publicación. Exponer exactamente qué falta y cómo se verificará desde otra red |

Si existe la URL pública al momento de la defensa, usarla en el recorrido y
agregar evidencia de salud, certificado, trigger y restauración **de ese servidor**.
Si no existe, reconocer que Etapa 8 no está cumplida; no ocultarlo con un túnel
al equipo local ni con el laboratorio HTTPS.

### EXPLAIN seguro y lectura de evidencia

Ejemplo S3 de solo lectura, en una base de defensa:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT cl.tipo_cliente, count(DISTINCT cl.id_cliente)
FROM bodegas_atuel.cliente cl
JOIN bodegas_atuel.comprobante c USING (id_cliente)
WHERE c.id_sala = 1 AND c.fecha BETWEEN CURRENT_DATE - 6 AND CURRENT_DATE
GROUP BY cl.tipo_cliente;
```

Es el núcleo de S3; la consulta completa añade tipos con cero compradores.
El docente puede observar otro plan en su entorno. Las mejoras de E son
mediciones fechadas, no una promesa de repetir exactamente los milisegundos.
No ejecutar EXPLAIN ANALYZE de DELETE sin transacción y rollback: ejecuta la sentencia.

## Veinte preguntas con respuestas vinculadas al proyecto

1. **¿Por qué PostgreSQL?** Necesitamos NUMERIC, FK/UNIQUE/CHECK, ENUM/DOMAIN,
   procedimientos, triggers diferidos, roles y EXPLAIN con buffers en el mismo
   motor. Se utilizan en `database/01`–`07`; no basta decir que es «robusto».
2. **¿Qué garantiza aquí la 3FN?** Bajo las DF declaradas, todo determinante
   no trivial es superclave o su dependiente es primo. Quitamos la tasa parcial
   del detalle y la provincia duplicada de Finca. No elimina toda redundancia
   agregada: `comprobante.total` sigue materializado y se reconoce como tal.
3. **¿PK, FK, UNIQUE y CHECK son equivalentes?** No. PK identifica y no admite
   NULL; FK exige una referencia; UNIQUE expresa otra clave, como documento del
   cliente; CHECK limita valores de una fila, como precio positivo y fechas del permiso.
4. **¿Qué clave tiene Parcela?** `(id_finca,numero_parcela)` en `02_tablas.sql`:
   el número solo distingue dentro de una finca. El lote referencia ambas columnas.
5. **¿Por qué triggers y no validación solo en API?** Las reglas deben actuar
   también con SQL directo. `05_triggers.sql` protege stock, estados, auditoría,
   composición e ISA, y las suites SQL acceden sin pasar por FastAPI.
6. **¿Por qué diferir la composición?** Un INSERT de vino precede a sus cepas.
   Comprobar después de cada sentencia rechazaría el estado intermedio legítimo;
   al COMMIT `fn_validar_composicion_vino` exige al menos una cepa y suma exacta 100.
7. **¿Cómo se garantiza la ISA?** PK/FK compartidas, discriminador, bloqueos de
   Cliente al cambiar subtipos y validación diferida de exactamente un subtipo
   compatible. No basta con tres FK independientes.
8. **¿Cómo se impide vender sin stock?** `tg_movimiento_stock_venta` realiza
   `UPDATE ... WHERE cantidad_stock >= cantidad`; si no afecta una fila, rechaza.
   El CHECK no negativo complementa, pero no reemplaza el débito condicional.
9. **¿Dos ventas simultáneas?** El UPDATE bloquea la fila. La segunda sesión
   espera y reevalúa con el saldo confirmado por la primera; falla y revierte
   su cabecera. La prueba I registra dos PIDs y una sola venta confirmada.
10. **¿Por qué READ COMMITTED alcanza en esa prueba?** La protección está en
    el UPDATE condicional atómico y el bloqueo de la fila, no en un SELECT previo
    sin bloqueo. SERIALIZABLE podría agregar abortos/reintentos, no sustituye la regla.
11. **¿Por qué precio y descuento históricos?** El vino y el cliente pueden
    cambiar después. Cada detalle conserva el precio de venta y la cabecera
    una tasa uniforme. U6 no debe reescribir comprobantes pasados.
12. **¿Dónde hay anomalías evitadas?** `Localidad.provincia` no se repite en
    Finca, y el descuento de una venta no se copia en todos sus renglones.
    Explicar la descomposición sin pérdida de `normalizacion.md`, no solo nombrar 3FN.
13. **¿U1 cumple literalmente el texto?** Implementa el recálculo histórico
    aprobado para este proyecto. La frase del enunciado admite otra lectura;
    la diferencia está registrada en `validacion_tpi.md`. No inventar un aval docente.
14. **¿D1/D5 cancelan físicamente stock?** No: son purgas históricas aprobadas
    del proyecto, no anulaciones. D1 borra cabecera elegible y detalles sin
    reintegro; D5 no resta ingreso procesado. Un DELETE directo de renglón de
    venta sí conserva el reintegro ordinario. Explicar el límite frente a RN-12.
15. **¿Por qué no se usa todo índice?** El costo depende de selectividad y
    tamaño. S8 lee casi todos los comprobantes y S5 solo 18 transferencias;
    el planificador puede preferir Seq Scan. E conserva el BRIN descartado y
    el costo de escritura con sus rangos, no afirma que todo índice acelere.
16. **¿Qué muestra EXPLAIN ANALYZE?** Ejecuta y muestra filas/tiempo reales,
    loops y rutas; BUFFERS muestra accesos a páginas. Los tiempos de nodos no
    se suman ingenuamente. D4 incluye costo de integridad de FK aunque su índice
    interno no aparezca en el plan principal; E lo corrobora con estadísticas.
17. **¿Por qué no hay ORM y cómo se evita inyección?** Lo exige el TPI. Las
    funciones de `api/repository.py` parametrizan valores; los identificadores
    variables vienen de listas cerradas y se componen con `psycopg.sql`.
    La prueba maliciosa del filtro devuelve vacío, no ejecuta DROP.
18. **¿Qué privilegios tiene API?** LOGIN miembro de `bodegas_api`, sin dueño,
    superusuario, CREATE de esquema ni escritura directa de stocks/auditoría/total.
    Los SECURITY DEFINER pertenecen al rol dueño NOLOGIN, fijan search_path y no
    se conceden a PUBLIC. Esos privilegios se consultan realmente, no se infieren del nombre.
19. **¿require y verify-full son iguales?** No. require cifra; verify-full valida
    cadena de confianza y nombre del servidor. El perfil I monta solo la CA en API
    y verifica SAN `db`. Nginx requiere aparte certificado válido para el dominio
    público; la CA de laboratorio no demuestra ese requisito.
20. **¿Cómo recuperamos datos y explicamos el hash de permisos?** Restauramos
    un custom dump en una base nueva y comprobamos conteos, controles y huellas.
    El ORDER BY regional cambia un stream sin cambiar filas; COLLATE C produce
    el mismo hash portable. Los roles globales/contraseñas se provisionan por
    separado. Hasta hacerlo en nube, solo está probada la recuperación local.

## Cierre honesto ante el docente

Mostrar el estado de las nueve etapas en la matriz, no una afirmación «100 %».
La URL pública, la demo en esa URL, los aportes de todos los integrantes y el
examen individual no pueden sustituirse por documentación. Los nombres
confirmados son dos; §2.1 pide 3–4: validar nómina/excepción con la cátedra,
sin fabricar identidades, autores, fechas ni commits.
