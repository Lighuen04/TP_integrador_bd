# Matriz definitiva de cumplimiento del TPI

Auditoría I: **10/11/2026**, referencia Git `9afb118c6874a25703d51e5fefd4095ee0e13ac7`.
Fuente: [consigna original](TPI_Bodegas_del_Atuel.md), especialmente §7, §8 y §10.
Resultados actuales: [fase I](evidencias/fase_i_resultados.json). Los resultados
B–H conservan su fecha y entorno; no se presentan como ejecuciones nuevas.

**I** = implementado; **P** = probado; **D** = documentado; **Pendiente** = falta
ejecución, confirmación o evidencia. `P local` no implica `P nube`. Una fila
I/D con ejecución pendiente no se cuenta como criterio de aceptación cumplido.

## Estado de las nueve etapas

| Etapa | Estado verificable | Qué impide declarar el cierre total |
|---|---|---|
| 1. Modelado | SQL/modelo/diccionario I/P/D; DER revisado parcialmente | Mínimos de participación y exportación/revisión nativa del DER pendientes |
| 2. Integridad | I/P/D local | Explicar la política histórica D1/D5 respecto de RN-12; no equivale a aval docente |
| 3. Carga | I/P/D local | Nube no ejecutada; no se redujo el dataset local |
| 4. Índices | I/P/D, experimento E conservado y fuentes verificadas | Tiempos son del entorno E; no se extrapolan al servidor futuro |
| 5. Consultas | I/P/D, cuatro archivos reejecutados en I con rollback | U1 conserva interpretación histórica; lectura literal requiere validación académica |
| 6. API | I/P/D local y Docker | Operaciones en URL pública pendientes |
| 7. Frontend | I/P/D local y Docker/Nginx | Navegación contra la URL pública pendiente |
| 8. Nube | Configuración I/D; TLS privado P local | Sin cuenta/VM/dominio autorizados; todos los criterios de nube pendientes |
| 9. Documentación/defensa | Informe y guion D; pruebas locales P; grupo de dos autorizado | Defensa real, demo en nube y acreditación de contribuciones reales pendientes |

## Requisitos verificables por etapa

### 1. Modelo y esquema — §7, Etapa 1

| Requisito / referencia | Implementación | Prueba o evidencia | Estado | Observación |
|---|---|---|---|---|
| DER coherente; entidades, atributos, claves, ISA y cardinalidades; pasos 1–2 | [DER editable](DER.drawio.xml), [trazabilidad](trazabilidad_der_relacional.md) | Inventario XML y revisión geométrica I; 22 entidades, 25 relaciones, 97 atributos | I/D; P parcial | Se corrigieron conectores, no semántica; los 48 rótulos máximos no expresan todos los mínimos |
| Entidad débil Parcela; paso 2 | DER doble contorno; PK `(id_finca,numero_parcela)` en [02](../database/02_tablas.sql) | SQL 08/09 y catálogo actual | I/P/D | Número de parcela no se presume único globalmente |
| ISA total/disjunta; paso 2 | Supertipo y tres subtipos; triggers diferidos | SQL 09; API clientes; catálogo I | I/P/D | Exactamente un subtipo coherente al COMMIT |
| Esquema relacional y claves; paso 3 | [DBML](modelo_relacional.dbml), [esquema escrito](esquema_relacional.md) | 29 tablas, 35 FK; catálogo I | I/P/D | Sin tablas de negocio nuevas en I |
| 3FN con DF justificadas; paso 4 | [normalizacion.md](normalizacion.md) | Revisión I de 29 relaciones y claves alternativas | D; revisión realizada | Demostración relativa a las DF declaradas; el trigger no demuestra 3FN |
| Diccionario coincide con SQL; paso 5 / aceptación | [Diccionario](diccionario_datos.md), [generador](../scripts/generar_diccionario.py) | Regenerado desde PostgreSQL y comparado byte a byte en I | I/P/D | 124 columnas, tipos, NULL, claves, defaults y restricciones |
| Creación desde cero; paso 7 / aceptación | `database/01`–`07`, extensión F `10` | Base Docker vacía creada para SQL 08/09; bootstrap TLS aislado I | I/P/D | No se reinstaló sobre datos activos |
| No FLOAT en importes; estados tipados / aceptación | NUMERIC y ENUM en [01](../database/01_tipos_dominios.sql), [02](../database/02_tablas.sql) | Catálogo y diccionario I | I/P/D | Tipos concretos, sin ORM |
| DER en imagen/PDF y fuente; entregables | XML editable; vista auxiliar [SVG](DER_revision.svg) | Inspección visual por áreas del render geométrico | D; P parcial | No es exportación nativa draw.io; trazado ortogonal aproximado, requiere revisión final del grupo |

### 2. Integridad y lógica — §4 y §7, Etapa 2

| Requisito / referencia | Implementación | Prueba o evidencia | Estado | Observación |
|---|---|---|---|---|
| PK en todas; todas las FK con acciones | [02](../database/02_tablas.sql) | Catálogo I y SQL 08/09 | I/P/D | 29 PK y 35 FK |
| NOT NULL, ≥4 UNIQUE adicionales, ≥8 CHECK con uno entre columnas, ≥3 DEFAULT | [01–03](../database/README.md#correspondencia-y-restricciones) | Catálogo I, SQL 08/09 | I/P/D | UNIQUE alternativos de vino, lote, cliente y transportista; CUIT de bodega ya es PK |
| ≥1 ENUM y ≥1 DOMAIN | [01](../database/01_tipos_dominios.sql) | Creación en laboratorio I y catálogo | I/P/D | Dos ENUM y dominio CUIT |
| ≥4 funciones y ≥2 procedimientos | [04](../database/04_funciones.sql) | SQL 09; ingreso/transferencia API y Docker I | I/P/D | Inventario de rutinas incluye funciones de trigger; no se cuenta todo como función de negocio |
| ≥6 triggers distintos, BEFORE/AFTER/diferido | [05](../database/05_triggers.sql) | 22 triggers; SQL 09 y composición 80 % al COMMIT | I/P/D | No se desactivaron para las pruebas operativas |
| ≥3 vistas | [07](../database/07_vistas.sql) | Catálogo I y reportes | I/P/D | Stock total, ventas mensuales, documentos pendientes |
| Propietario, API, reportes y mínimos privilegios | [03](../database/03_restricciones.sql), cierre de propiedad [07](../database/07_vistas.sql) | SQL 09; privilegios reales y TLS con LOGIN API | I/P/D | Owner NOLOGIN; API sin escritura directa de stock/auditoría/total |
| Cada RN-01–15 tiene mecanismo y caso | [Informe §3](informe_integracion_final.md#3-integridad-trazabilidad-y-concurrencia) | SQL 09 y suites API/navegador I | I/P/D | D5 es excepción de purga documental, no modificación operativa de detalle cerrado |
| Concurrencia dos sesiones, con/sin bloqueo, aislamiento; paso 8 | [script](../scripts/probar_concurrencia.py) | Reejecutado en I: 1 COMMIT, 1 ROLLBACK, stock final 0; comparación aislada SELECT FOR UPDATE | I/P/D local | No modifica el modelo ni desactiva triggers; demostrar oralmente las sesiones/PIDs |

### 3. Carga — §7, Etapa 3

| Requisito / referencia | Implementación | Prueba o evidencia | Estado | Observación |
|---|---|---|---|---|
| Todas las tablas pobladas; ≥3 >10.000 y ≥1 >100.000 | [Generador C](../database/seed/generar_datos.py) | Conteos actuales I: 357.894 filas; 29 tablas, 4 >10.000 y 2 >100.000 | I/P/D local | Los volúmenes por entidad y 500.000 renglones son recomendaciones, no mínimos obligatorios |
| Misma semilla produce mismos datos | Generador, cinco CSV y fecha explícita | C comparó dos cargas; H/I comparan datos y hashes portables | I/P/D | Permisos requiere COLLATE C al comparar Windows/local con en_US.utf8 de Docker |
| Integridad, estados, saldos y totales válidos | [validador C](../database/seed/validar_carga.sql) | 26 controles I sin incidencias | I/P/D | Validador del perfil de carga, no de cualquier dataset con nuevas ventas |
| Comparar INSERT por fila y lotes; explicar triggers | [README C](../database/seed/README.md) | C/E y sus tiempos conservados | I/P/D previo; fuentes verificadas | No se declara un benchmark nuevo en I |

### 4. Índices — §7, Etapa 4

| Requisito / referencia | Implementación | Prueba o evidencia | Estado | Observación |
|---|---|---|---|---|
| ≥5 secundarios: compuesto, parcial, FK y variante | [06](../database/06_indices.sql) | 24 secundarios + 33 automáticos, catálogo I | I/P/D | No confundir 57 totales con 57 diseñados por el grupo |
| ≥3 mejoras con EXPLAIN ANALYZE BUFFERS y baseline PK/UNIQUE | [Informe E](informe_rendimiento_indices.md) | S2, S3 y D4; planes completos [JSON E](evidencias/fase_e_indices.json) | I/P/D previo; fuentes verificadas | Mismo código y datos; versiones/entorno y fechas de las mediciones se conservan |
| Orden de columnas, índice descartado, no utilizado y costo de escritura | Mismo informe E | BRIN descartado; parcial ignorado con 18 transferencias; muestras de escritura | I/P/D previo | Rangos de escritura superpuestos; no afirmar penalización universal |

### 5. Consultas — §7, Etapa 5 y §8

| Requisito / referencia | Implementación | Prueba o evidencia | Estado | Observación |
|---|---|---|---|---|
| U1–U6, I1–I6, D1–D6, S1–S12 comentadas | [consultas/](../consultas/) | Cuatro archivos reejecutados I; 30 consignas; rollback y 29 huellas iguales | I/P/D | Conteos de fecha móvil pueden cambiar respecto del corte D/E |
| Escrituras BEGIN/control/ROLLBACK | UPDATE/INSERT/DELETE anteriores | Ejecución I sin cambio persistente | I/P/D | No se ejecutaron purgas sobre la base activa |
| Avanzadas S9–S12 | [select.sql](../consultas/select.sql) | CTE, subconsulta correlacionada, agregados, RANK y acumulados | I/P/D | No se resolvieron filtrando en JavaScript |
| U1 literal: descuento que corresponde al tipo | [04](../database/04_funciones.sql), [decisión documentada](validacion_tpi.md) | Recálculo histórico probado | I/P/D; conformidad literal pendiente | Se preserva descuento histórico por decisión del proyecto; no se atribuye aprobación docente |

### 6. API — §7, Etapa 6

| Requisito / referencia | Implementación | Prueba o evidencia | Estado | Observación |
|---|---|---|---|---|
| Driver nativo, SQL parametrizado y capa propia | [repository.py](../api/repository.py) | API e inyección tratada como texto | I/P/D | Sin ORM; identificadores variables limitados y citados con psycopg.sql |
| Pool, transacciones y rol API | [database.py](../api/database.py) | Rollback multirrenglón y fallo diferido antes del HTTP exitoso | I/P/D | No conexiones globales compartidas |
| Rutas mínimas vinos/clientes/comprobantes/ingresos/transferencias/reportes/salud | [main.py](../api/main.py), OpenAPI | 22 pruebas API y flujo Docker I | I/P/D local | `/catalogos` es auxiliar de solo lectura |
| Filtros/paginación, errores SQLSTATE y OpenAPI | API y Pydantic | Pruebas de filtros, 23502/23503/23001/23505/23514/22023 y desconexión | I/P/D | Otros SQLSTATE están mapeados, no todos fueron inducidos en pruebas |
| ≥8 pruebas y ≥3 reglas DB; inyección fallida | [tests](../api/tests/) | 22 pruebas API; varias reglas reales, no solo Pydantic | I/P/D | No afirmar que un 422 de forma demuestra un CHECK de PostgreSQL |
| Compose base/API de un comando | [Compose](../docker-compose.yml) | Bootstrap de laboratorio I desde vacío; servicios activos comprobados | I/P/D local | No es un despliegue público |

### 7. Frontend — §7, Etapa 7

| Requisito / referencia | Implementación | Prueba o evidencia | Estado | Observación |
|---|---|---|---|---|
| Cinco pantallas mínimas y gráfico de ventas | [frontend/](../frontend/README.md) | 14 pruebas de navegador y Nginx Docker I | I/P/D local | HTML/CSS/JS nativos, sin dependencias de gráficos |
| Mostrar errores DB, venta sin stock sin parciales, no calcular importes | [app.js](../frontend/app.js), [api.js](../frontend/api.js) | Venta válida/negativa, composición 80 %, transferencia y caída real | I/P/D | Los valores definitivos vienen de PostgreSQL |
| Capa HTTP configurable, boceto e integración Compose | Frontend y Dockerfile/Nginx | Configuración, responsive y navegación de teclado | I/P/D | Mismo origen; no CORS abierto |

### 8. Nube — §7, Etapa 8, requisitos/pasos/aceptación

| Requisito / referencia | Implementación o preparación | Evidencia disponible | Estado | Qué falta |
|---|---|---|---|---|
| Comparar ≥2 proveedores y elegir sin gastos obligatorios; paso 1 | [Informe §8](informe_integracion_final.md#8-despliegue-seguridad-y-límites) | Documentación oficial reconsultada I; usuario confirma ausencia de infraestructura | D | Obtener una VM académica sin facturación; Oracle candidato condicional, no alta realizada |
| PostgreSQL, API y frontend ejecutándose en nube | [perfil Compose TLS](../deploy/compose.https.yml) | Topología local y laboratorio TLS aislado | I/D; nube pendiente | Cuenta/VM autorizada; no crear ni contratar recursos sin autorización |
| URL pública HTTPS con certificado válido | [Nginx HTTPS](../deploy/nginx.https.conf) | HTTPS privado local con CA de laboratorio; confianza pública rechazada como corresponde | I/D; nube pendiente | Dominio real y certificado de CA pública; prueba desde otra red |
| Conexión DB cifrada y restringida; aceptación | verify-full, CA y clave privada por servicio | pg_stat_ssl TLS 1.3; nombre y CA incorrectos rechazados en laboratorio I | I/P/D local; nube pendiente | Repetir en VM, verificar firewall y acceso externo a 5432 denegado |
| Roles, secretos, migraciones y datos en nube | Scripts SQL y configuración de secretos existentes | SQL/bootstrap/carga locales comprobados | I/D; nube pendiente | Ejecutar en el servidor; no subir .env ni reducir datos sin límite justificado |
| Backup/restauración y regla con trigger en nube; pasos 8–9 | [herramientas](../scripts/operar_docker.py) | Respaldo restaurado y regla negativa I en copias locales | I/P/D local; nube pendiente | Ejecutar y conservar evidencia en la nube; local no satisface este criterio |
| URL y pasos reales en README; paso 10 | [README](../README.md) | Estado pendiente explícito, sin URL ficticia | D | Incorporar URL solo después de verificarla |

### 9. Informe, demo y defensa — §7, Etapa 9 y §10

| Requisito / referencia | Archivo | Evidencia disponible | Estado | Observación |
|---|---|---|---|---|
| README e informe final con estructura §10.2 | [Informe único](informe_integracion_final.md), README | Portada confirmada, índice de temas y enlaces verificables | D | No se creó un segundo informe duplicado |
| Trazabilidad RN→mecanismo→prueba; paso 3 | Informe §3 y esta matriz | RN-01–15 y suites SQL/API | I/P/D | Contrastar observaciones históricas con texto literal |
| Demo de 10–15 minutos sobre nube; paso 4 | [Guion](guion_defensa.md) | Ensayos técnicos locales; comandos reproducibles | D; realización pendiente | Debe repetirse en URL pública cuando exista |
| Defensa individual; paso 5 | Guion con 20 preguntas y respuestas de código | Material preparado, no examen realizado | D; realización pendiente | Cada integrante debe explicar y operar, no solo leer |
| Cantidad de integrantes; §2.1 | Amigo L. y Perez M. | El usuario confirmó que la cátedra autorizó el grupo de dos | Cumplido por autorización | No se exige agregar integrantes ni se atribuye una constancia documental al docente |
| Commits y aportes de todos; §10.3 | Historial Git real, informe §9 | Los alias Git no identifican por sí solos a personas o aportes académicos | Acreditación pendiente | Conservar autores e historial; acreditar contribuciones reales, sin commits ni atribuciones ficticios |

No se consideran obligatorios un framework frontend, JWT, microservicios, una
rama por fase ni el volumen recomendado de 500.000 renglones. Sí son obligatorios
los mínimos de volumen, las cinco pantallas, el pool, las pruebas, la URL pública
HTTPS y la participación/defensa que fija el enunciado.

El **principal requisito técnico pendiente es el despliegue público en la nube
con HTTPS**. No existe una URL pública verificada; el laboratorio TLS local no
es producción. Se mantienen la revisión nativa del DER y la defensa oral como
tareas de revisión final. La cantidad de dos integrantes ya está autorizada,
según confirmación del usuario; no se inventa una constancia docente.
