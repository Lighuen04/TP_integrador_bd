# Bodegas del Atuel — informe de integración final

Cierre técnico local del 9 de noviembre de 2026. Este documento reúne los
entregables existentes y completa los faltantes, siguiendo §10.2 de la
[consigna original](TPI_Bodegas_del_Atuel.md). La
[evidencia H](evidencias/fase_h_resultados.json) contiene resultados ejecutados,
no estimaciones. La entrega global no se declara terminada: queda la publicación
con HTTPS y la revisión/defensa del grupo.

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

- [DER original editable](DER.drawio.xml), copia exacta del archivo fuente existente.
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

## 3. Integridad, trazabilidad y concurrencia

La definición ejecutable está en `database/01`–`07`; F añadió únicamente la baja
acotada de vino sin movimientos en `10_api_baja_vino.sql`. H no cambia esas
funciones, restricciones, tablas, triggers, índices ni consultas aprobadas.

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

Fuentes oficiales consultadas: [Oracle Free Tier](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm),
[validación de cuenta Oracle](https://www.oracle.com/cloud/free/faq/),
[límites Render Free](https://render.com/docs/free). Los límites se revisan antes
de crear recursos; no se garantiza gratuidad por una captura histórica.

**Decisión técnica preparada:** reutilizar Compose en una VM gratuita/educativa
ya autorizada; Oracle Always Free es el candidato si el grupo obtiene capacidad
sin contratar recursos pagos. Si no la obtiene, debe escoger y validar otra
cuenta/proveedor. No se creó ninguna instancia, DNS, certificado público ni URL.
La limitación es acceso a cuenta/servidor/dominio, no una prueba local pendiente.

### Configuración HTTPS/TLS preparada

`deploy/compose.https.yml` reutiliza los tres servicios: Nginx escucha 443,
PostgreSQL activa SSL y la API conecta con `DB_SSLMODE=require`. Las rutas se
comparten con la configuración local, sin añadir gateway ni CORS amplio.

En una VM Linux autorizada, después de verificar que sus recursos no son pagos:

1. Clonar el repositorio, instalar Docker/Compose y configurar `.env` con secretos nuevos.
2. Asignar un dominio a la IP real de la VM y obtener un certificado público válido por el mecanismo del proveedor/ACME. No usar autofirmado para afirmar HTTPS público válido.
3. Crear un directorio privado `TLS_DIR` fuera de Git con `web.crt` (cadena completa), `web.key`, `postgres.crt` y `postgres.key`. El certificado interno puede ser de una CA propia; `require` cifra pero no acredita por sí mismo la identidad del servidor.
4. Proteger las claves. `postgres.key` debe ser propiedad del usuario postgres del contenedor con modo 0600, o root/grupo postgres con 0640. Determinar UID/GID con `docker compose run --rm --no-deps --entrypoint id db postgres`; no suponer un UID fijo. Mantener permisos de lectura de Nginx para su clave.
5. Exportar `TLS_DIR` absoluto y ejecutar `docker compose -f docker-compose.yml -f deploy/compose.https.yml config --quiet`, luego `up -d --build` con los mismos dos archivos. Compose >=2.24.4 soporta el reemplazo de puertos usado.
6. Abrir solo HTTPS 443 y SSH restringido a operadores en firewall/reglas del proveedor. No publicar 5432; la API directa continúa limitada a loopback. Provisionar roles y cargar/restaurar una base nueva por los procedimientos del README.
7. Verificar desde otra red la URL real, certificado, `/api/salud`, una operación con trigger, rechazo de acceso al puerto de la base y cifrado de la sesión API mediante `pg_stat_ssl`. Registrar la evidencia y la política de renovación antes de declarar el despliegue completo.
8. Guardar el respaldo también fuera de la VM y repetir una restauración; un volumen no sustituye un respaldo.

La combinación Compose se valida sintácticamente; **el perfil TLS no se arrancó
con certificados públicos ni en una VM externa**. La instalación local utiliza
HTTP y red Docker privada: no se presenta como conexión pública HTTPS/TLS probada.
Referencia de [permisos de claves PostgreSQL](https://www.postgresql.org/docs/18/ssl-tcp.html).

## 9. Conclusiones y pendientes de entrega

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
| HTTPS y PostgreSQL cifrado en nube | Configuración preparada; publicación/validación externas pendientes |
| Revisión conceptual y defensa individual | El grupo debe revisar cardinalidades visuales y preparar la demo oral |
| Commits de todos los integrantes | No se atribuyen contribuciones inexistentes; verificar participación real del grupo |

Guion mínimo de defensa (10–15 minutos): mostrar DER/decisión 3FN, catálogo y
composición inválida, venta válida/sin stock, transferencia, plan S2 o S3 del
informe E, prueba de última botella y restauración. En la entrega definitiva
esa demo debe repetirse sobre la URL de nube; una demo local no la reemplaza.
