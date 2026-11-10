# Bodegas del Atuel — informe de integración final

**Universidad Tecnológica Nacional — Facultad Regional San Rafael**
**Ingeniería en Sistemas · Bases de Datos · 3.º año · ciclo 2026**
**Trabajo Práctico Integrador: Bodegas del Atuel**
Integrantes confirmados por el usuario: **Amigo L. — Perez M.**
Comisión y docente: no confirmados en las fuentes; no se inventan.
Actualización de auditoría y preparación de defensa: **10 de noviembre de 2026**.

Cierre técnico local H del 9 de noviembre y revalidación I del 10. Este documento reúne los
entregables existentes y completa los faltantes, siguiendo §10.2 de la
[consigna original](TPI_Bodegas_del_Atuel.md). La
[evidencia H](evidencias/fase_h_resultados.json) conserva su corte histórico;
la [evidencia I](evidencias/fase_i_resultados.json) registra las comprobaciones
actuales. La entrega global no se declara terminada: quedan publicación pública,
revisión nativa del DER y defensa oral. El principal requisito técnico pendiente
es el despliegue público en la nube con HTTPS: no existe una URL pública verificada
y el laboratorio TLS local no constituye producción. La cátedra autorizó el grupo
de dos integrantes, según confirmación del usuario; la cantidad no es un
incumplimiento ni requiere agregar personas. No se atribuye una constancia
documental al docente. Los alias Git no se convierten en nombres académicos.

### Índice académico de cobertura

| Tema solicitado | Desarrollo y fuente verificable |
|---|---|
| 1. Portada | Encabezado anterior, únicamente datos confirmados |
| 2. Introducción y objetivos | §1 |
| 3. Requisitos | [Matriz definitiva](matriz_cumplimiento_tpi.md), con referencias al TPI |
| 4–7. Modelo conceptual, relacional, normalización y diccionario | §2 y documentos enlazados |
| 8–11. Integridad, funciones/procedimientos, triggers y vistas | §3, inventario y matriz RN |
| 12. Carga masiva | §4 y README del generador único |
| 13–14. Consultas e índices/rendimiento | §6 y §5, con fuentes y planes |
| 15–16. API y frontend | §7 y contratos/documentación existentes |
| 17–18. Concurrencia, Docker y arquitectura | §3 y §1/§7 |
| 19–21. Recuperación, seguridad y despliegue | §8; local comprobado y nube pendiente diferenciados |
| 22–23. Resultados y conclusiones | §9, evidencias I y matriz |

La [defensa de 14 minutos y sus 20 preguntas](guion_defensa.md) es material de
preparación; no acredita que los integrantes ya rindieron la defensa.

## 1. Introducción y alcance

El sistema permite consultar vinos, administrar etiquetas, emitir ventas y
procesar transferencias. PostgreSQL garantiza las reglas incluso fuera de la
API. No se incorporaron ORM, autenticación ajena al TPI, microservicios ni pagos.
La estructura de carpetas sugerida por §10.1 se implementa como `database/` y
`frontend/`; sus nombres son una sugerencia, no un motivo para duplicar código.

Docker Desktop funciona realmente en esta fase: base y API saludables, Nginx
sirviendo el frontend en **127.0.0.1:8081**. El diagnóstico de indisponibilidad
de F/G es histórico. Se conservaron el volumen `base_de_datos_postgres_data`,
la base inicial vacía `bodegas` y las bases originales de mediciones.

## 2. Modelo, fuentes y diccionario

- [DER editable](DER.drawio.xml), fuente original con correcciones puntuales de conectores en I; versión original conservada en Git `9afb118`.
- [Vista SVG auxiliar](DER_revision.svg): geometría del XML revisada por áreas, no exportación nativa draw.io.
- [Modelo relacional DBML](modelo_relacional.dbml), 29 tablas.
- [Normalización y dependencias](normalizacion.md).
- [Trazabilidad DER–relacional](trazabilidad_der_relacional.md) y [decisiones](validacion_tpi.md).
- [Diccionario de 29 tablas y 124 columnas](diccionario_datos.md), derivado del catálogo PostgreSQL con [su script](../scripts/generar_diccionario.py).

El diccionario incluye tipos, nulabilidad, defaults/identity, PK/FK, CHECK/UNIQUE,
acciones referenciales, descripciones y triggers diferidos reales. No modifica
la base ni reconstruye un DER especulativo. Los rótulos de cardinalidad del XML
original no están unidos estructuralmente a sus conectores: la revisión visual
final del grupo sigue siendo necesaria. Localidad–Finca conserva la decisión
1:N aprobada en el proyecto.

En I se conectaron los óvalos existentes zona_cobertura→Distribuidor,
descuento_10%→Socio e ID_auditoria/precio_nuevo→Auditoría. Dos mitades que
compartían el mismo punto se unieron en el conector Ingreso–contiene–Vino.
Se verificó que los 193 vértices, sus valores, estilos, posiciones y los 48
rótulos 1/N/M permanecen iguales; hay 151 conectores completos en vez de 152
segmentos con seis extremos ausentes. No se cambió SQL ni ninguna cardinalidad.

No hay ejecutable draw.io disponible: la inspección visual se realizó sobre una
representación local de las coordenadas, cuyo enrutamiento ortogonal automático
es aproximado. Queda abrir/exportar el XML en el editor nativo y cerrar mínimos
de participación no inequívocos. No se declara una validación visual nativa total.

## 3. Integridad, trazabilidad y concurrencia

La definición ejecutable está en `database/01`–`07`; F añadió únicamente la baja
acotada de vino sin movimientos en `10_api_baja_vino.sql`. H no cambia esas
funciones, restricciones, tablas, triggers, índices ni consultas aprobadas.

Inventario para la defensa: funciones de negocio `fn_descuento_tipo`,
`fn_descuento_cliente`, `fn_total_comprobante`, `fn_stock_sala` y
`fn_antiguedad_anios`; procedimientos `sp_procesar_ingreso` y
`sp_procesar_transferencia`. Los 22 triggers incluyen BEFORE/AFTER y restricciones
diferidas; el total de 26 rutinas también cuenta funciones de trigger y la baja F,
por lo que no equivale a 26 funciones de negocio. Las tres vistas son
`vw_stock_total_vino`, `vw_ventas_mensuales_sala` y `vw_documentos_pendientes`.

| Regla | Mecanismo | Prueba/archivo existente |
|---|---|---|
| RN-01 | CHECK de precio positivo | SQL 09, caso RN-01/RN-15; API precio negativo |
| RN-02 | FK sala→localidad, encargado en localidad | SQL 09, RN-02/RN-03 |
| RN-03 | FK obligatoria empleado→sala | SQL 09, RN-02/RN-03 |
| RN-04 | FK parcela→cepa y UNIQUE parcela/campaña | SQL 09, RN-04 |
| RN-05 | Constraint trigger diferido de suma 100 % | SQL 09, RN-05; navegador composición 80 % |
| RN-06 | Trigger de descuento y validación ISA diferida | SQL 09, RN-06/U6/ISA; clientes y venta histórica API |
| RN-07 | CHECK vencimiento posterior a emisión | SQL 09, RN-07 |
| RN-08 | Total por trigger con precio/descuento históricos | SQL 09, RN-08/RN-09; venta API/navegador |
| RN-09 | UPDATE condicional atómico de stock | SQL 09; última botella H con dos sesiones |
| RN-10 | Estados y procedimiento de ingreso | SQL 09, RN-10; API ingreso una sola vez |
| RN-11 | Fecha protegida y procedimiento de transferencia | SQL 09, RN-11; transferencia real por Nginx |
| RN-12 | Protección de renglones fuera de confección | SQL 09, RN-12/B.2; API renglón procesado |
| RN-13 | Auditoría AFTER UPDATE de precio | SQL 09, RN-13; edición desde navegador |
| RN-14 | FK RESTRICT de maestros con movimientos | SQL 09, RN-14; baja protegida API |
| RN-15 | CHECK y dominio CUIT | SQL 08/09; precio, graduación y stock inválidos |

Referencias: [SQL 08](../database/08_pruebas_integridad.sql),
[SQL 09](../database/09_pruebas_reglas_negocio.sql), [API](../api/tests/test_api.py),
[navegador](../frontend/tests/test_frontend.py). La guía de qué regla corresponde
a CHECK/FK/trigger/función/procedimiento se conserva en [database/README.md](../database/README.md).
La política D1/D5 de eliminación histórica y U1 con descuento histórico no se
alteraron; sus interpretaciones y límites ya están documentados allí.

### Dos sesiones y la última botella

[Script reproducible](../scripts/probar_concurrencia.py), solo sobre
`bodegas_h_pruebas_*`. El fixture crea un vino e ingresa/transfiere una botella
mediante los procedimientos existentes. Dos conexiones independientes del LOGIN
API operan en READ COMMITTED; A mantiene su débito sin confirmar un segundo
mientras B intenta vender la misma botella. A confirma; B espera y PostgreSQL
revalida `cantidad_stock >= cantidad`, rechaza con 23514 y revierte su cabecera.

Resultado real: stock **1 → 0**, **un COMMIT**, **un ROLLBACK**, una cabecera y
un renglón. No hay stock negativo ni comprobante parcial. La espera se observa
en los tiempos y PIDs distintos del JSON. No se desactiva ningún trigger.

Para la comparación académica sin/con bloqueo se usa una tabla separada
`h_demostracion.saldo_sin_triggers`, únicamente en esa copia. Sin bloqueo,
ambas sesiones leen 1 y confirman una reserva escribiendo el mismo saldo 0:
dos reservas para una botella. Con `SELECT FOR UPDATE`, una confirma y la otra
lee saldo 0. Esa tabla didáctica no pertenece a las 29 relaciones de negocio.

## 4. Carga masiva y validación

La base configurada al comenzar tenía 29 tablas y **cero filas**. Se eligió
crear `bodegas_c_docker_demo`, instalar el SQL vigente y ejecutar el **mismo**
generador C, semilla 42 y fecha 2026-11-09, mediante una imagen de herramientas
Python independiente. No se creó un segundo generador. La excepción histórica
acotada de fechas de transferencia es la ya documentada en C; los triggers
quedaron activos y los 26 controles devolvieron cero incidencias.

La carga tardó **85,444 s**, sin presentar este tiempo como benchmark comparable
con el equipo Windows de C. Produjo **357.894 filas**, todas las tablas pobladas,
cuatro >10.000 filas y dos >100.000. No hay diferencia de conteo que atribuir a
un perfil reducido. De las 29 huellas originales, 28 coinciden directamente.
`permiso_exportacion` conserva las mismas 16.665 filas, pero su hash cambia por
el ORDER BY de códigos: las bases locales usan locale `C` y Docker `en_US.utf8`.
Se repitió COPY ordenando con `COLLATE "C"`: el SHA coincide en Docker y en las
tres bases C originales (`9f074ca9…ce136d0f7`). Se conserva la evidencia anterior,
no se modifica la colación de datos ni se confunde el orden del stream con datos
diferentes. [Semántica de colaciones PostgreSQL](https://www.postgresql.org/docs/18/collation.html).
Las huellas lógicas excluyen reloj/usuario de auditoría igual que C; ID y precios
sí forman parte de la comparación.

| Tabla principal | Filas |
|---|---:|
| cliente | 20.000 |
| permiso_exportacion | 16.665 |
| comprobante | 100.001 |
| comprobante_vino | 200.002 |
| Total de las 29 tablas | 357.894 |

El JSON conserva los 29 conteos/huellas y la validación de ISA, composición,
precios y descuentos históricos, totales, FK/UNIQUE/CHECK, existencias actuales
e históricas y estados. La aplicación activa usa esa base. Las escrituras de
concurrencia e integración ocurrieron en copias restauradas, que sí incluyen
filas adicionales H: no se confunden sus conteos con el dataset de referencia.

Catálogos, orden de carga, COPY, estrategia de triggers y benchmark INSERT/COPY:
[informe de carga existente](../database/seed/README.md).

## 5. Índices y rendimiento

Se conserva el [informe único E](informe_rendimiento_indices.md), con planes,
buffers, medianas y costo de escritura: 24 índices secundarios y 33 automáticos.
S2, S3 y D4 muestran las tres mejoras claras; BRIN fue descartado. El índice
parcial no se usó con 18 transferencias y no se le atribuye una mejora ficticia.
H no repite ni modifica el experimento para obtener resultados más favorables.

## 6. Consultas SQL

[UPDATE](../consultas/update.sql), [INSERT](../consultas/insert.sql),
[DELETE](../consultas/delete.sql), [SELECT](../consultas/select.sql): 30 consignas
comentadas y verificadas en D/E. Se preservan I1 con mínimo global idempotente,
I3 sin omisión de vinos faltantes, división relacional, CTE, ranking/acumulados,
agregación independiente de asociaciones N:M y los borrados D1/D5 aprobados.
Evidencia previa: [fase D](evidencias/fase_d_consultas.json).

## 7. API, frontend e integración final

Los contratos y errores están en [API](../api/README.md) y los flujos en
[frontend](../frontend/README.md). SQL parametrizado, LOGIN API sin privilegios
de propietario, COMMIT antes del éxito HTTP y mensajes de negocio conservados.
Las cinco pantallas no calculan totales, descuentos ni stock. La inyección SQL
en filtros se verifica como texto; un intento XSS se muestra sin ejecutarlo.

Se volvieron a ejecutar **22 pruebas API y 14 de navegador**, más las suites SQL
08/09 en una base Docker vacía con salida 0 y rollback de sus fixtures. Además se probó
la cadena **Edge → Nginx → FastAPI → PostgreSQL Docker**, con imágenes reales y
una copia restaurada: catálogo, filtros/paginación, detalle, alta/edición/auditoría,
rechazo al COMMIT de composición 80 %, venta 1039,50 calculada en PostgreSQL,
venta multirrenglón fallida sin débito parcial, transferencias válida/inválida,
reportes con diez vinos y seis salas, Swagger y desconexión real de la API.

Defectos concretos corregidos en H: Nginx esperaba demasiado al conectar con
una API detenida; se limita a tres segundos. El frontend no clasificaba 504 como
indisponibilidad; ahora conserva un mensaje útil para 502/503/504. El fallback
genérico se sustituyó por rutas API explícitas para Swagger y 404 para archivos
o rutas innecesarios. Se verificó que `.env`, código interno y `/redoc` no se sirven.
Los contenedores/red de las pruebas se retiraron; no se detuvo la API activa
para simular una caída ni se escribieron ventas en el dataset activo.

## 8. Despliegue, seguridad y límites

### Seguridad local y respaldo probados

Las contraseñas de ejemplo se rotaron realmente en PostgreSQL y `.env`, sin
borrar el volumen ni imprimir secretos. Se volvió a conectar el LOGIN API y
la cuenta administrativa. El operador debe proteger `.env` y su equipo; no se
confunde el cambio de variable con un ALTER ROLE sobre un volumen existente.
Se revisaron privilegios de stock/totales/DDL, propiedad y search_path de rutinas
SECURITY DEFINER, puertos e ignorados de Git/contexto Docker.

Se generó un dump custom de **2.320.442 bytes**, conservado fuera de Git en
`.local/backups/fase_h_demo.dump`, y se restauró en una base nueva mediante
`pg_restore --single-transaction --exit-on-error`. Las 29 huellas, conteos y
26 controles coincidieron antes de las escrituras de prueba. Los roles globales
no forman parte de un pg_dump por base: en otro clúster deben provisionarse por
un administrador. [Procedimiento probado de respaldo](../README.md#respaldo-y-restauración-verificados).
Fundamento: [pg_dump y restauración](https://www.postgresql.org/docs/18/backup-dump.html).

### Comparación y decisión para nube — pendiente de cuenta externa

| Alternativa | Condiciones verificadas y adecuación |
|---|---|
| Oracle Cloud Always Free, VM | Permite conservar Compose y administración PostgreSQL completa; requiere cuenta y validación con tarjeta. La disponibilidad regional no está garantizada y las instancias inactivas pueden recuperarse por el proveedor. No asumir capacidad gratuita disponible. |
| Render Free, servicios gestionados | Soporta servicios Docker y URL pública; el PostgreSQL gratuito vence a los 30 días y los servicios web gratuitos tienen suspensión por inactividad. Implica adaptar la distribución de los tres componentes y revisar permisos del PostgreSQL gestionado. |

Actualización de opciones reconsultadas el 10/11/2026:

| Aspecto | Oracle Always Free, VM | Render Free |
|---|---|---|
| Registro/tarjeta | Cuenta y verificación con tarjeta; no se realizó el alta | Cuenta de servicio; puede operar sin medio de pago con suspensión al exceder límites; no se introdujo tarjeta |
| Recursos | A1: 1.500 OCPU-h/9.000 GB-h mensuales, equivalentes a 2 OCPU/12 GB; 200 GB de bloque, sujetos a región/cupo | 750 horas web/mes por workspace; PostgreSQL 1 GB |
| Persistencia | Volumen PostgreSQL administrado por el grupo, con backup externo; riesgo de recuperación de instancias inactivas | PostgreSQL Free vence a 30 días; no usar filesystem efímero del servicio web como disco de PostgreSQL |
| Docker/HTTPS | Reutiliza este Compose; el grupo provisiona dominio y certificado válido | Acepta imágenes Docker por servicio y TLS gestionado; no ejecuta nuestro Compose completo como una VM |
| Costos/límites | No activar plan pago ni superar recursos elegibles; disponibilidad gratuita no garantizada | No introducir pago; servicios se suspenden o DB expira. Requiere adaptar distribución y validar roles |

Fuentes oficiales consultadas: [Oracle Free Tier](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm),
[validación de cuenta Oracle](https://www.oracle.com/cloud/free/faq/),
[límites Render Free](https://render.com/docs/free). Los límites se revisan antes
de crear recursos; no se garantiza gratuidad por una captura histórica.

**Decisión técnica preparada:** priorizar una VM académica sin facturación
otorgada y autorizada; reutiliza Compose sin adaptar la aplicación. El usuario
confirmó en I que no existe infraestructura. Oracle Always Free es candidato si el grupo obtiene capacidad
sin contratar recursos pagos. Si no la obtiene, debe escoger y validar otra
cuenta/proveedor. No se creó ninguna instancia, DNS, certificado público ni URL.
La limitación es acceso a cuenta/servidor/dominio, no una prueba local pendiente.

### Configuración HTTPS/TLS preparada

`deploy/compose.https.yml` reutiliza los tres servicios: Nginx escucha 443,
PostgreSQL activa SSL y la API conecta con `DB_SSLMODE=verify-full` y
`DB_SSLROOTCERT=/run/tls/ca.crt`. Cada contenedor monta solo su certificado/clave
o CA correspondiente; la API no recibe claves privadas. Las tres políticas de
reinicio son `unless-stopped`. Las rutas se
comparten con la configuración local, sin añadir gateway ni CORS amplio.

En una VM Linux autorizada, después de verificar que sus recursos no son pagos:

1. Clonar el repositorio, instalar Docker/Compose y configurar `.env` con secretos nuevos.
2. Asignar un dominio a la IP real de la VM y obtener un certificado público válido por el mecanismo del proveedor/ACME. No usar autofirmado para afirmar HTTPS público válido.
3. Crear un directorio privado `TLS_DIR` fuera de Git con `web.crt` (cadena pública completa), `web.key`, `postgres.crt`, `postgres.key` y `ca.crt` (CA emisora del certificado PostgreSQL). El certificado PostgreSQL debe incluir SAN DNS `db` para el nombre usado por la API. Conservar la clave de la CA fuera del directorio montado y no instalar la CA de laboratorio como confianza pública.
4. Proteger las claves. `postgres.key` debe ser propiedad del usuario postgres del contenedor con modo 0600, o root/grupo postgres con 0640. Determinar UID/GID con `docker compose run --rm --no-deps --entrypoint id db postgres`; no suponer un UID fijo. Mantener permisos de lectura de Nginx para su clave.
5. Exportar `TLS_DIR` absoluto y ejecutar `docker compose -f docker-compose.yml -f deploy/compose.https.yml config --quiet`, luego `up -d --build` con los mismos dos archivos. Compose >=2.24.4 soporta el reemplazo de puertos usado.
6. Abrir solo HTTPS 443 y SSH restringido a operadores en firewall/reglas del proveedor. No publicar 5432; la API directa continúa limitada a loopback. Provisionar roles y cargar/restaurar una base nueva por los procedimientos del README.
7. Verificar desde otra red la URL real, certificado, `/api/salud`, una operación con trigger, rechazo de acceso al puerto de la base y cifrado de la sesión API mediante `pg_stat_ssl`. Registrar la evidencia y la política de renovación antes de declarar el despliegue completo.
8. Guardar el respaldo también fuera de la VM y repetir una restauración; un volumen no sustituye un respaldo.

En I se ejecutó el perfil con una CA privada de laboratorio y puertos/volúmenes
aislados para no tocar el proyecto activo. HTTPS devolvió 200 y PostgreSQL
negoció TLS 1.3 con verify-full; una CA o nombre incorrectos se rechazaron. La
clave PostgreSQL tenía modo 0600/propietario postgres y Nginx pasó su validación.
En Windows se usaron volúmenes POSIX propios para las claves, en lugar de asumir
que un bind mount conserva chmod. Los volúmenes del laboratorio se conservan;
sus contenedores/red se retiraron. El proyecto activo continúa en HTTP 8081.

**No se arrancó el perfil con certificados públicos ni en una VM externa**.
La CA privada fue aceptada solo al suministrarla explícitamente al cliente y
rechazada por la confianza pública predeterminada. Esto no acredita Etapa 8.
Reproducción local: `python scripts/probar_tls_local.py` (OpenSSL local requerido).
Referencia de [verify-full e identidad de servidor](https://www.postgresql.org/docs/18/libpq-ssl.html).
Referencia de [permisos de claves PostgreSQL](https://www.postgresql.org/docs/18/ssl-tcp.html).

## 9. Conclusiones y pendientes de entrega

### Revalidación I del 10/11/2026

Pasaron **36 pruebas API/navegador en 30,29 s**, las suites SQL 08/09 y los
cuatro archivos de las 30 consultas aprobadas sobre una copia con rollback.
La integración con Nginx real completó nueve comprobaciones sin errores
JavaScript. Concurrencia confirmó una sola venta de la última botella; el
respaldo custom de 2.320.442 bytes se restauró y verificó antes de esas escrituras.
La base activa conserva las 357.894 filas y sus 29 huellas nativas de H, con
26 controles sin incidencias. El catálogo actual tiene 124 columnas, 29 PK,
35 FK, cuatro UNIQUE adicionales, 24 CHECK y cinco defaults; el diccionario
regenerado coincide byte a byte. Los tiempos del experimento E se conservan
como mediciones históricas, sin atribuirles una nueva ejecución en I.
Los detalles y las huellas están en la [evidencia I](evidencias/fase_i_resultados.json).

El mismo generador produjo los mismos datos en Windows/local y Linux/Docker;
la comparación de hashes de texto debe fijar una colación portable.
La restauración y la concurrencia demuestran propiedades distintas: recuperar
datos y evitar doble venta no se infieren de que un contenedor esté saludable.
Las pruebas de caída detectaron un defecto de experiencia de usuario que no
aparecía con el proxy Python; se corrigió y verificó con Nginx real.

| Entregable | Estado |
|---|---|
| Modelo, integridad, carga, consultas, índices | Implementados, probados y documentados; ver cierres B–E |
| API y cinco pantallas | Implementadas, probadas localmente y con Nginx/PostgreSQL Docker |
| Concurrencia y restauración | Ejecutadas realmente, scripts y resultados conservados |
| DER editable y diccionario | Fuente original conservada; diccionario físico completo derivado |
| HTTPS privado y PostgreSQL verify-full | Probados en laboratorio I; no equivalen a nube |
| HTTPS y PostgreSQL cifrado en nube | Publicación/validación externas pendientes por infraestructura inexistente |
| Revisión conceptual y defensa individual | El grupo debe revisar cardinalidades visuales y preparar la demo oral |
| Commits de todos los integrantes | Historial real detallado debajo; correspondencia con personas/aportes pendiente |

### Historial real hasta el inicio de I

| Commit | Autor registrado | Fecha de autor | Descripción |
|---|---|---|---|
| `06a8118` | Lighuen | 15/05/2026 | Initial commit |
| `0542743` | Lighuen04 | 09/11/2026 | Base PostgreSQL y API REST |
| `d4464a8` | Lighuen04 | 09/11/2026 | Frontend e integración G |
| `9afb118` | Lighuen04 | 09/11/2026 | Integración local y documentación H |

Son dos alias, no prueba de dos personas distintas ni atribución a Amigo L. o
Perez M. No se modificaron autores/fechas ni se fabricaron commits. Cada
integrante debe realizar aportes reales revisables y acreditar su autoría;
la cantidad de dos integrantes ya está autorizada por la cátedra, según
confirmación del usuario. Comisión, docente, defensa realizada y demo pública
no se completan por inferencia.

Guion mínimo de defensa (10–15 minutos): mostrar DER/decisión 3FN, catálogo y
composición inválida, venta válida/sin stock, transferencia, plan S2 o S3 del
informe E, prueba de última botella y restauración. En la entrega definitiva
esa demo debe repetirse sobre la URL de nube; una demo local no la reemplaza.
