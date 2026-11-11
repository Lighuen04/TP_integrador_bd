# Bodegas del Atuel — TPI Bases de Datos

Sistema académico de gestión vitivinícola: modelo de 29 tablas, integridad en
PostgreSQL, carga reproducible, API REST con SQL directo y cinco pantallas web.
La consigna original se conserva en [docs/TPI_Bodegas_del_Atuel.md](docs/TPI_Bodegas_del_Atuel.md).

**Estado:** la aplicación está publicada en [Render](https://bodegas-atuel-web.onrender.com) con PostgreSQL en Neon. Se hicieron pruebas manuales de consulta, venta y respaldo/restauración; quedan verificaciones de seguridad y permisos. Las pruebas locales y su corte histórico permanecen en [el informe](docs/informe_integracion_final.md), [evidencias H](docs/evidencias/fase_h_resultados.json) y [auditoría I](docs/evidencias/fase_i_resultados.json).

La [matriz de las nueve etapas](docs/matriz_cumplimiento_tpi.md) y el
[guion de defensa de 14 minutos con 20 preguntas](docs/guion_defensa.md)
completan la preparación de entrega. Integrantes confirmados: **Amigo L. — Perez M.**
La cátedra autorizó el grupo de dos integrantes, según confirmación del usuario;
la cantidad no es un requisito pendiente. Comisión y docente requieren confirmación.
El laboratorio I comprobó HTTPS con CA privada y PostgreSQL `verify-full`,
incluidos rechazos por CA y nombre incorrectos; son pruebas locales independientes del despliegue público.

## Arquitectura y tecnologías

Local: navegador → **Nginx :8081** → **FastAPI** → **PostgreSQL 18**. En nube: navegador → frontend estático Render → API Render → PostgreSQL Neon.

Frontend HTML/CSS/JavaScript con Fetch nativo; Python, Pydantic, Uvicorn,
psycopg 3 y pool. Sin ORM ni framework frontend. Totales, descuentos históricos,
stock, estados, auditoría y composición se resuelven en PostgreSQL.
PostgreSQL solo se comunica en la red Docker; no publica un puerto al host.
Las interfaces locales se enlazan a `127.0.0.1`.

## Requisitos y configuración

- Docker Engine y Docker Compose funcionando (Docker Desktop con contenedores Linux en Windows).
- Para herramientas/pruebas: Python 3.11+ recomendado y entorno virtual; también se probó Python 3.9.13.
- Edge instalado o Chromium de Playwright para pruebas de navegador.

Desde la raíz, **solo si todavía no existe `.env`**:

```powershell
Copy-Item .env.example .env
```

Editar `.env` fuera de Git: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`,
`DB_PASSWORD` y `POSTGRES_PASSWORD`. Los valores de contraseña del ejemplo son
marcadores: reemplazarlos por secretos diferentes antes del primer arranque.
Compose fija el host interno `db` y el puerto `5432`; `DB_HOST/DB_PORT` del ejemplo
también sirven para la alternativa local. No sobrescribir un `.env` existente.
El LOGIN API recibe únicamente membresía de `bodegas_api`; nunca usar el dueño
ni `postgres` para atender HTTP. `.env`, entornos, respaldos y datos locales no
se versionan ni se incluyen en las imágenes.

## Iniciar con Docker

```powershell
docker compose config --quiet
docker compose up -d --build
docker compose ps
```

- Frontend: <http://127.0.0.1:8081>.
- Swagger: <http://127.0.0.1:8081/docs>.
- OpenAPI: <http://127.0.0.1:8081/openapi.json>.
- Salud: <http://127.0.0.1:8081/api/salud>.
- API directa, para diagnóstico local: <http://127.0.0.1:8000/docs>.

El puerto `8081` reemplaza al `8080`, bloqueado en este Windows. En un volumen
nuevo, Docker ejecuta `database/01`–`07`, `10_api_baja_vino.sql` y el bootstrap
del LOGIN. En un volumen existente **no reinstala ni migra automáticamente**.
Los healthchecks ordenan el arranque de base, API y frontend. No ejecutar
`docker compose down -v` para actualizar código o credenciales.

## Inicio rápido en Windows

1. Instala **Docker Desktop para Windows** con soporte para contenedores Linux y
   espera a que Docker indique que está en funcionamiento. No hace falta abrir
   PowerShell ni instalar Python para iniciar la aplicación.
2. Desde el Explorador de archivos, haz doble clic en `Iniciar_Bodegas.bat`,
   ubicado en la raíz del proyecto. El iniciador comprueba Docker y Compose,
   valida la configuración y espera a que PostgreSQL, la API y la web estén
   disponibles; luego abre <http://127.0.0.1:8081>.
3. En una primera ejecución, el iniciador solicita dos contraseñas distintas
   (ocultas mientras se escriben) y crea `.env` a partir de `.env.example`.
   Usa al menos 20 caracteres con letras, números o `. _ ! @ % + -`. `.env`
   contiene credenciales locales y no debe compartirse ni versionarse. Si `.env`
   ya existe, el iniciador nunca lo reemplaza: configura sus credenciales
   manualmente y vuelve a iniciarlo. No arranca si detecta los marcadores de
   ejemplo.

Al comenzar aparece el menú en español para iniciar, detener, reiniciar,
consultar el estado, abrir la interfaz o la documentación de FastAPI, ver
registros y consultar conteos. La primera opción se ejecuta automáticamente al
abrir el `.bat`; el menú queda disponible al finalizar.

Para detener el proyecto, selecciona **2. Detener el sistema**. Se usa
`docker compose down` sin `-v`: se quitan contenedores y red, pero se conserva el
volumen `postgres_data` con la base. Al iniciar de nuevo se reutilizan los datos;
el generador masivo no se ejecuta y PostgreSQL no vuelve a aplicar los SQL de
inicialización sobre un volumen ya creado. No borres el volumen desde Docker
Desktop si quieres conservar la información.

Si Docker no responde, abre Docker Desktop, espera a que termine de iniciar y
elige reintentar. Si Docker CLI no está instalado, instala Docker Desktop por
los canales oficiales; el iniciador no descarga ni instala programas. Ante un
fallo de salud, revisa el estado y los últimos registros desde el menú; también
comprueba que los puertos locales `8000` y `8081` estén libres.

Para validar en forma segura, usa una copia de trabajo sin `.env` para probar
su creación y `docker compose config --quiet`. Con Docker Desktop cerrado,
comprueba que el iniciador permita reintentar o salir. Después de iniciar,
anota los conteos de la opción 8 y vuelve a iniciar: los servicios saludables
no deben recrearse ni cambiar los conteos. Al detener, `docker compose down`
debe conservar `postgres_data`. No es necesario borrar ni reinicializar bases.

## Herramientas y carga masiva

```powershell
python -m venv .venv
.venv/Scripts/python.exe -m pip install -r api/requirements-test.txt
.venv/Scripts/python.exe scripts/operar_docker.py conteos
```

Si las 29 tablas de la base activa están vacías, crear una **base nueva** y
reutilizar el generador C, con semilla 42 y fecha explícita:

```powershell
.venv/Scripts/python.exe scripts/operar_docker.py cargar --base bodegas_c_docker_demo --fecha-ref 2026-11-09 --reporte .local/h/carga.json
.venv/Scripts/python.exe scripts/operar_docker.py activar --base bodegas_c_docker_demo
.venv/Scripts/python.exe scripts/operar_docker.py validar --fecha-ref 2026-11-09
```

El nombre debe ser nuevo; CREATE falla si ya existe. El comando de carga
rechaza bases activas con datos, no las vacía. Construye una imagen temporal de
herramientas con el generador y sus dependencias, sin agregar dependencias a la
API. `activar` actualiza únicamente `DB_NAME` en `.env` y reinicia API/frontend;
conserva la base anterior y el volumen. Si ya hay datos, **conservarlos**, revisar
sus conteos y no repetir la carga. El validador C verifica su perfil de datos,
no cualquier dataset modificado por ventas de demostración.

En esta ejecución, `bodegas` quedó vacía y preservada; la aplicación usa
`bodegas_c_docker_demo`. Tiene los mismos datos que C: 20.000 clientes,
100.001 comprobantes, 200.002 renglones y 16.665 permisos, entre otras tablas.
Las escrituras H se hicieron en copias `bodegas_h_pruebas_*`, no en la base activa
ni en las bases originales de mediciones. [Detalle de carga C](database/seed/README.md).
De los hashes originales, 28 coinciden directamente; el de permisos depende del
ordenamiento regional. Al comparar sus códigos con `COLLATE "C"`, también coincide.
`validar` conserva la huella original y agrega esa verificación portable.

## Cambiar credenciales sin borrar el volumen

Cambiar `POSTGRES_PASSWORD` en `.env` **no cambia** una contraseña de un volumen
ya inicializado. El procedimiento probado genera dos secretos aleatorios,
ejecuta ALTER ROLE por stdin con registro de sentencias deshabilitado para esa
sesión, actualiza `.env` y recrea API/frontend, sin imprimir los valores:

```powershell
.venv/Scripts/python.exe scripts/operar_docker.py rotar-credenciales
docker compose up -d
```

En H se ejecutó y se comprobó la conexión con las nuevas credenciales.
Restringir el acceso al `.env` al usuario operador; en Linux, `chmod 600 .env`.
Alternativa manual: `psql` interactivo y `\password` para cada cuenta, seguido
de actualización privada de `.env` y recreación de API/frontend. No introducir
contraseñas en argumentos, historial de comandos, capturas ni informes.

## Respaldo y restauración verificados

```powershell
.venv/Scripts/python.exe scripts/operar_docker.py backup --archivo .local/backups/demo.dump
.venv/Scripts/python.exe scripts/operar_docker.py restaurar --base bodegas_h_restaurada_demo --archivo .local/backups/demo.dump
.venv/Scripts/python.exe scripts/operar_docker.py validar --base bodegas_h_restaurada_demo --fecha-ref 2026-11-09
```

Se usa `pg_dump --format=custom` y `pg_restore --single-transaction
--exit-on-error`, con transporte binario sin pasar por redirección de PowerShell.
No se sobrescriben archivos ni bases existentes. Los roles ya existen en el mismo
clúster; para otro clúster un administrador debe provisionar primero los tres
roles grupales y el LOGIN API, sin exportar sus contraseñas. Un dump por base
no respalda roles globales. Guardar una copia del respaldo fuera del equipo;
los volcados grandes no pertenecen al repositorio.

## Pruebas

```powershell
.venv/Scripts/python.exe -m pip install -r api/requirements-ui.txt
$env:TEST_DB_PORT='55441'  # PostgreSQL local de pruebas; 5432 en otra instalación
$env:UI_BROWSER_CHANNEL='msedge'
.venv/Scripts/python.exe -m pytest api/tests -q --basetemp=.local/pytest_h_api
.venv/Scripts/python.exe -m pytest frontend/tests -q --basetemp=.local/pytest_h_ui
.venv/Scripts/python.exe scripts/operar_docker.py probar-sql --base bodegas_h_pruebas_sql_nueva
```

Estas suites necesitan PostgreSQL local accesible y una cuenta administrativa
de preparación (`TEST_DB_HOST/PORT/ADMIN/PASSWORD`); **la API bajo prueba utiliza
un LOGIN sin privilegios de dueño**. Crean y limpian solo sus propias bases.
Para Chromium, omitir el canal e instalarlo con `python -m playwright install chromium`.

Para repetir las pruebas **con Nginx y PostgreSQL Docker reales**, restaurar
una copia con nombre nuevo y ejecutar:

```powershell
.venv/Scripts/python.exe scripts/operar_docker.py restaurar --base bodegas_h_pruebas_nueva --archivo .local/backups/demo.dump
.venv/Scripts/python.exe scripts/probar_concurrencia.py --base bodegas_h_pruebas_nueva
.venv/Scripts/python.exe scripts/probar_integracion_docker.py --base bodegas_h_pruebas_nueva
```

La integración reutiliza los formularios y crea contenedores/red temporales;
solo detiene su API temporal para probar la desconexión. Al terminar retira
esos contenedores/red, sin borrar volúmenes. La copia de prueba queda para
inspección. Usar otra base nueva para una segunda ejecución, porque sus
documentos de prueba ya existen. La concurrencia incluye dos sesiones sobre la
última botella y una comparación sin/con `SELECT FOR UPDATE` en una tabla
académica aislada del esquema de las 29 tablas.

## Documentación y estructura

| Ruta | Contenido |
|---|---|
| `database/` | DDL, permisos, funciones, triggers, índices, vistas y suites SQL |
| `database/seed/` | Único generador masivo, CSV, validador e imagen de herramientas |
| `consultas/` | Las 30 consignas U/I/D/S aprobadas |
| `api/` | API, SQL parametrizado, esquemas, pool y pruebas |
| `frontend/` | Cinco pantallas, Nginx y pruebas de navegador |
| `scripts/` | Operación Docker, diccionario, concurrencia e integración |
| `deploy/` | Configuración HTTPS/TLS alternativa para una VM externa |
| `docs/` | Fuentes, modelo, normalización, diccionario, informes y evidencias |

[DER original editable](docs/DER.drawio.xml) · [Modelo relacional](docs/modelo_relacional.dbml) ·
[Normalización](docs/normalizacion.md) · [Diccionario derivado de PostgreSQL](docs/diccionario_datos.md) ·
[Reglas y decisiones](database/README.md) · [Índices medidos](docs/informe_rendimiento_indices.md) ·
[API](api/README.md) · [Frontend](frontend/README.md).

## Despliegue público en Render y Neon

- **Aplicación web:** https://bodegas-atuel-web.onrender.com
- **API:** https://tp-integrador-bd.onrender.com
- **Salud:** https://bodegas-atuel-web.onrender.com/api/salud
- **Arquitectura:** frontend estático en Render, reescritura `/api/*` hacia FastAPI en Render y PostgreSQL 18 en Neon (São Paulo). La API utiliza un usuario de base con rol de aplicación; las contraseñas permanecen en la configuración del servicio, fuera de Git.
- **Configuración:** servicio Python con raíz del repositorio, build `pip install -r api/requirements.txt` y arranque `uvicorn api.main:app --host 0.0.0.0 --port $PORT`. El sitio estático publica `public_web` generado con `mkdir -p public_web && cp frontend/*.html frontend/*.js frontend/*.css public_web/`; la regla Rewrite `/api/*` apunta a `https://tp-integrador-bd.onrender.com/*`.
- **Variables privadas de la API:** `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` y `DB_SSLMODE`; no incluir valores secretos en el repositorio.

### Comprobaciones de la puesta en marcha

Durante la sesión guiada del 10/11/2026 se observó la respuesta `api: ok, postgresql: ok`; el catálogo, detalle de vino, filtro por cepa y tablero mostraron datos. Se rechazó una venta sin stock y se consultó que no existiera el comprobante de prueba. Una venta válida se registró con total $847. No se verificó mediante comparación antes/después el saldo de stock. La prueba es manual, no reemplaza las suites automatizadas.

La carga inicial reportó 20.000 clientes, 100.001 comprobantes y 200.002 renglones. Antes de la venta válida se generó un respaldo `pg_dump` formato custom fuera del repositorio y se restauró en una base Neon separada. Ambas operaciones devolvieron código 0; en la copia se observaron los tres conteos anteriores y 29 tablas, 3 vistas y 22 triggers. La restauración usó `--single-transaction --exit-on-error --no-owner --no-acl`: no acredita la recuperación de propietarios ni permisos. Los conteos no verifican por sí solos todos los datos; el respaldo es anterior a la venta de prueba. Los roles globales deben respaldarse o recrearse aparte.

### Límites y tareas pendientes

- El servicio gratuito de Render puede suspenderse por inactividad y demorar al reanudarse; se observó un error transitorio antes de una respuesta de salud correcta. Evaluar la recuperación del pool y repetir las pruebas tras inactividad.
- La conexión actual de la API utiliza `DB_SSLMODE=require`; cifra la conexión, pero no demuestra verificación de identidad del servidor como `verify-full`. Quedan por verificar certificado y configuración efectiva, restricciones de acceso de Neon y pruebas desde otra red.
- La API de demostración está expuesta públicamente y tiene operaciones de escritura sin autenticación de usuario; usar únicamente datos ficticios y restringir el acceso o incorporar protección antes de un uso real. Rotar la credencial administrativa de Neon que se expuso durante la puesta en marcha.
- Verificar recuperación de roles, propietarios y privilegios en un entorno aislado; guardar otra copia del respaldo fuera del equipo y documentar su proceso. Comprobar también un flujo con permisos restaurados.
- La adaptación local del generador para aceptar `neondb` se ejecutó fuera de las migraciones oficiales y no es una guía reproducible versionada; no desactivar controles ni volver a cargar una base con datos.
- El enlace `/docs` del frontend y los demás recorridos, incluido el procesamiento de transferencias, deben verificarse en el despliegue. La revisión del DER, las interpretaciones U1/D1/D5 y la defensa siguen pendientes según el informe.

La revisión nativa de cardinalidades del DER, la acreditación de aportes y la defensa individual deben ser realizados o confirmados por el grupo.

