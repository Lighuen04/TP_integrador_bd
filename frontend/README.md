# Frontend — Fase G

HTML, CSS y JavaScript con módulos y Fetch nativo. No requiere npm, compilación,
frameworks, fuentes externas ni bibliotecas de gráficos. `api.js` concentra HTTP;
`app.js` controla la interacción y crea nodos con `textContent`. El gráfico de
ventas usa barras CSS y una tabla con los mismos valores recibidos del backend.

## Iniciar el sistema

Con Docker Desktop funcionando, desde la raíz:

```powershell
Copy-Item .env.example .env
# Editar .env: reemplazar las contraseñas y definir DB_NAME y DB_USER.
docker compose config --quiet
docker compose up --build
```

Frontend: <http://127.0.0.1:8080>. Swagger: <http://127.0.0.1:8080/docs>.
PostgreSQL no publica un puerto al host. Nginx sirve los cuatro archivos del
frontend y deriva `/api/` a la API dentro de la red de Compose.
Las rutas originales de OpenAPI también se derivan a la API si no corresponden
a archivos estáticos, para que Swagger pueda ejecutar operaciones desde `/docs`.
Las comprobaciones de salud ordenan PostgreSQL → API → frontend. No se eliminan volúmenes ni se
migran datos automáticamente. En un volumen nuevo se instala el esquema vacío;
los datos se cargan mediante el proceso aprobado de [fase C](../database/seed/README.md).
Sin datos, la interfaz muestra estados vacíos, no inventa etiquetas ni clientes.

**Estado comprobado en esta fase:** `docker compose config` es válido; se intentó
`docker compose up`, pero Docker Desktop Linux Engine no estaba disponible.
El arranque de los tres contenedores y el proxy Nginx quedan sin verificar.
La integración completa sí se probó localmente, con navegador, proxy de desarrollo,
Uvicorn, cuenta API y PostgreSQL reales.

### Alternativa local sin Docker

Preparar la base y las variables `DB_*` según [api/README.md](../api/README.md),
con una cuenta LOGIN miembro de `bodegas_api`, sin privilegios administrativos.
En una terminal:

```powershell
.venv/Scripts/python.exe -m uvicorn api.main:app --host 127.0.0.1 --port 8000
```

En otra:

```powershell
.venv/Scripts/python.exe frontend/servir.py --puerto 8080 --api http://127.0.0.1:8000
```

Abrir <http://127.0.0.1:8080>. El servidor de desarrollo usa solo la biblioteca
estándar de Python y mantiene el mismo origen; no es un servidor de producción.
No abrir `index.html` mediante `file://`, porque utiliza módulos JavaScript.
La URL base se configura en el meta `api-base` de `index.html` (predeterminada
`/api`), o definiendo `window.API_BASE_URL` antes de cargar `app.js`. Nunca contiene
credenciales de PostgreSQL. Para otro origen se necesitaría CORS explícito en la
API; la configuración entregada evita esa necesidad.

## Cinco pantallas

Boceto común: navegación lateral → título y acciones → formulario o resultados.
En móvil, la navegación pasa a una fila desplazable y las tablas conservan su
propio desplazamiento horizontal, sin desbordar la página.

| Pantalla | Flujo |
|---|---|
| Catálogo | Filtros → tabla paginada → ficha modal con composición, maridajes y stock; búsqueda por código exacto |
| Gestión | Datos del vino → renglones de composición → guardar; edición y baja confirmada |
| Venta | Cliente y sala → renglones → confirmar → comprobante y total devueltos por PostgreSQL |
| Transferencias | Crear → cargar renglones → terminar → procesar, con acciones habilitadas según el estado real |
| Reportes | Ranking, ventas trimestrales con gráfico y tabla, vinos sin stock por sala y transportista activo |

Los filtros y la paginación se envían a `/vinos`. Los clientes se consultan por
páginas de 20, con botones para recorrerlas. Las sugerencias de códigos de vino
corresponden a la página de catálogo recibida; también se puede ingresar cualquier
código exacto o agregar un vino a la venta desde su ficha. No se descarga todo el
catálogo para filtrar en el navegador.

Se añadió únicamente `GET /catalogos`, de solo lectura, con salas, cepas y
bodegas existentes. El resto consume las rutas de la fase F: `/vinos`,
`/clientes`, `/comprobantes`, `/transferencias`, `/reportes/*` y `/salud`.

### Probar una venta

Abrir Nueva venta, ingresar un número nuevo, elegir cliente y sala y completar
los códigos/cantidades. Confirmar. El formulario no envía precio ni descuento;
el comprobante muestra precio histórico, descuento y total de la respuesta real.
Para un caso negativo, pedir un vino sin saldo en la sala: se muestra el mensaje
de stock y no aparece una venta confirmada. La API revierte cabecera y renglones.

### Probar una transferencia

Ingresar número nuevo y sala de destino. Crear, agregar cada renglón, terminar y
procesar. Los renglones agregados se guardan individualmente en confección; el
procesamiento completo es atómico. Si falta stock en depósito, el estado sigue
en `terminado` y se muestra el error de la base. No se modifica stock en JavaScript.
La navegación entre secciones conserva la solicitud activa; recargar la página
pierde esa selección, porque la API actual no ofrece consulta de transferencias.
No se simula recuperar una solicitud ni se permite suponer un estado por código.

### Errores y seguridad

Se muestra `detalle` de la API como mensaje principal. Incluye composición 80 %,
duplicados, dependencias, stock y estados inválidos. Los errores de conexión no
se presentan como operaciones exitosas; el botón de estado permite reintentar.
Los formularios conservan sus datos ante un fallo y bloquean el doble envío
mientras esperan. Antes de una baja hay una confirmación accesible con teclado.
La suma visual del corte es informativa: incluso 80 % llega a PostgreSQL para
que el constraint diferido decida. El frontend no calcula totales, descuentos
ni movimientos de stock.

## Pruebas reproducibles

```powershell
.venv/Scripts/python.exe -m pip install -r api/requirements-ui.txt
$env:TEST_DB_PORT='55441' # 5432 para una instalación convencional
$env:UI_BROWSER_CHANNEL='msedge' # Edge instalado; omitir para Chromium de Playwright
.venv/Scripts/python.exe -m pytest api/tests -q --basetemp=.local/pytest_g_api
.venv/Scripts/python.exe -m pytest frontend/tests -q --basetemp=.local/pytest_g_ui
```

Si se usa Chromium de Playwright, instalarlo previamente con
`python -m playwright install chromium`. Las dependencias de navegador se usan
solo para pruebas; no se cargan en el frontend ni en la imagen de producción.
Los parámetros administrativos de preparación son `TEST_DB_HOST`, `TEST_DB_PORT`,
`TEST_DB_ADMIN`, `TEST_DB_PASSWORD`; la cuenta administrativa nunca atiende HTTP.

Las pruebas crean una base y un LOGIN únicos, reutilizan la instalación y limpieza
de F e incorporan fixtures explícitos para paginación y un intento XSS. Inician
Uvicorn y el proxy, abren Edge/Chromium y usan formularios reales, sin mocks de
respuestas. Consultan PostgreSQL para comprobar que los fallos no dejan ventas
ni cambios parciales de stock. Cortan realmente la API en el último caso para
verificar el mensaje de desconexión. Se elimina solo la base creada por la suite.

Resultados y límites: [evidencia G](../docs/evidencias/fase_g_resultados.json).
Capturas de escritorio, reportes y móvil se generan en `.local/g/`; los datos
de esas capturas son fixtures guardados en PostgreSQL, no respuestas simuladas.
Etapa 7 implementada y probada localmente; queda verificar el empaquetado Compose
con su motor disponible. No se realizó despliegue en la nube (fase H).
