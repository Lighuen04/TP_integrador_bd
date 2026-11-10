# API REST — Fase F

Extensión mínima G: `GET /catalogos` devuelve `salas`, `cepas` y `bodegas` de
solo lectura para los formularios. Se conserva `/clientes` paginado. Ahora hay
27 operaciones sobre 21 rutas de recursos. No cambia el esquema ni los procedimientos de la base.
El [frontend](../frontend/README.md) consume `/api/` mediante un proxy del mismo
origen; no necesita CORS abierto. Swagger también es accesible desde su `/docs`.

FastAPI, Pydantic, Uvicorn, psycopg 3 y psycopg_pool; SQL directo en un único
`repository.py`, sin ORM. `main.py` contiene rutas y traducción de errores,
`database.py` administra el pool y las transacciones y `schemas.py` valida la
forma del pedido y documenta las respuestas. Pruebas en `tests/`.

## Preparación y ejecución local

Se recomienda Python 3.11 o superior; el código también funciona con el Python
3.9.13 disponible en este entorno, donde se ejecutó la validación real.
Desde la raíz del proyecto:

```powershell
python -m venv .venv
.venv/Scripts/python.exe -m pip install -r api/requirements.txt
```

Instalar primero `database/01`–`07` según [las instrucciones de base](../database/README.md).
Luego ejecutar con una cuenta administrativa autorizada:

```powershell
psql -X -v ON_ERROR_STOP=1 -d <base> -f database/10_api_baja_vino.sql
```

La cuenta de conexión debe ser LOGIN, sin privilegios administrativos y con
membresía de `bodegas_api`, **nunca** de `bodegas_propietario`. Los scripts del
modelo crean roles grupales NOLOGIN; el administrador provisiona la cuenta
real, asigna una contraseña por su mecanismo seguro y concede
`GRANT bodegas_api TO bodegas_app`. No convertir el rol propietario en LOGIN.

Configurar las cinco variables de [`.env.example`](../.env.example) en la sesión:

```powershell
$env:DB_HOST='127.0.0.1'
$env:DB_PORT='5432'
$env:DB_NAME='bodegas'
$env:DB_USER='bodegas_app'
# DB_PASSWORD se configura fuera del repositorio, mediante el mecanismo del entorno.
.venv/Scripts/python.exe -m uvicorn api.main:app --host 127.0.0.1 --port 8000
```

La ejecución local lee variables de entorno; no carga `.env` automáticamente.
Swagger: <http://127.0.0.1:8000/docs>. OpenAPI: `/openapi.json`.
Salud: `/salud`, 200 si la consulta a PostgreSQL funciona, 503 ante pérdida de
conexión o agotamiento del pool. Una configuración inválida impide el arranque.
No se registra ni se devuelve la contraseña.

## Endpoints

| Recurso | Operaciones |
|---|---|
| Vinos | `GET/POST /vinos`, `GET/PUT/DELETE /vinos/{codigo}` |
| Clientes | `GET/POST /clientes`, `GET/PUT/DELETE /clientes/{identificador}` |
| Comprobantes | `POST /comprobantes`, `GET /comprobantes/{numero}` |
| Transferencias | `POST /transferencias`, `POST /transferencias/{numero}/renglones`, `/terminar`, `/procesar` |
| Ingresos | `POST /ingresos`, `POST /ingresos/{codigo}/renglones`, `/terminar`, `/procesar` |
| Reportes | `GET /reportes/top-vinos`, `/ventas-por-sala`, `/vinos-sin-stock?sala=1`, `/transportista-activo`, `/trazabilidad/{codigo}` |
| Salud | `GET /salud` |
| Catálogos auxiliares G | `GET /catalogos` |

Hay 27 operaciones sobre 21 rutas de recursos, además de la documentación de
FastAPI. Vinos y clientes aceptan `limite` (1–100, predeterminado 20) y `offset`
(desde cero). Vinos permite filtros combinados `tipo`, `cepa` (ID), `bodega`
(CUIT) y `anada`. El orden estable es la PK; no se filtra en memoria.

`POST` devuelve 201, las bajas exitosas 204, recursos inexistentes 404. `PUT`
reemplaza los campos editables completos, incluida la composición de vinos;
los IDs se toman de la URL. Los campos calculados o históricos no se aceptan
en los pedidos. Los importes/porcentajes Decimal de los esquemas de respuesta
se serializan como cadenas decimales para conservar precisión.

Ejemplo de venta (el precio y el descuento no forman parte del pedido):

```json
{
  "numero_comprobante": "API-001",
  "id_cliente": 1,
  "id_sala": 1,
  "renglones": [{"codigo_vino": "V001", "cantidad": 2}]
}
```

Cliente requiere identificación, nombre, tipo, documento, dirección y código
postal. Distribuidor requiere además zona y habilitación; exportador, país.
Los NOT NULL de cada subtipo rechazan datos faltantes. La transacción cambia
supertipo y subtipo juntos; las FK impiden cambios que rompan permisos asociados.

## Transacciones y reglas de PostgreSQL

Pool de 1–5 conexiones por proceso, espera máxima de 5 segundos; consultas de
hasta 15 segundos y espera de bloqueo de 5 segundos. Cada petición usa una
conexión y `conn.transaction()`: BEGIN, COMMIT o ROLLBACK reales. La dependencia
usa `scope="function"`, por lo que el COMMIT, incluidos los triggers diferidos,
termina antes de enviar una respuesta exitosa. No se comparten conexiones entre
peticiones ni se dejan transacciones abiertas.

Se reutilizan `sp_procesar_ingreso` y `sp_procesar_transferencia`. Los triggers
existentes inicializan descuentos, capturan el descuento histórico, validan la
ISA y composición, mueven stock, recalculan totales y auditan precios. La API
consulta el precio dentro del INSERT SQL; no calcula importes, descuentos ni
saldos. Cada venta completa se confirma o revierte con todos sus renglones.
El pool no realiza reintentos automáticos de escrituras: ante 503, el consumidor
debe comprobar el resultado por identificador antes de repetir una operación.

Los reportes reutilizan S1, S6, S7, S8 y el enfoque S9 de agregados separados y
`vw_stock_total_vino`. Trazabilidad muestra ficha, ingresos y transferencias
realmente vinculados al código. El modelo no relaciona lotes consumidos con un
vino específico: no se inventa esa relación ni se cambian tablas para simularla.
Las consultas SQL aprobadas no fueron modificadas.

### Única extensión indispensable: baja de vino sin movimientos

Todo INSERT de vino genera automáticamente una fila `stock_deposito` en cero.
Su FK RESTRICT hacía imposible borrar incluso un vino recién creado; el rol
API, correctamente, no tiene DELETE sobre stocks. `10_api_baja_vino.sql` añade
una única función SECURITY DEFINER, propiedad del rol NOLOGIN propietario y
con search_path fijo. Bloquea el vino, elimina exclusivamente su saldo de
depósito **cero**, asociaciones de composición/maridaje y finalmente el vino.
No elimina movimientos, auditoría, stock de sala ni saldo de depósito positivo:
las FK existentes rechazan la operación y todo se revierte. No modifica las
29 tablas, restricciones, índices ni triggers operativos, y no concede DML
directo de stock al rol API. EXECUTE se revoca de PUBLIC y se concede solo a API.

Se probaron baja válida, rechazo por auditoría y rechazo con stock/movimientos,
incluida la conservación de composición y saldos tras el fallo. La extensión
se instala solo en bases nuevas de prueba durante esta fase; para usarla en una
base existente hay que ejecutar el script anterior como administrador autorizado.

## Errores

Formato uniforme: `{"detalle":"mensaje comprensible","sqlstate":"23514"}`.
Los errores de forma tienen `sqlstate: null`. Nunca se envían SQL interno,
DETAIL de PostgreSQL, CONTEXT ni trazas Python.

| SQLSTATE | HTTP |
|---|---|
| 23505, 23503, 23001 (RESTRICT), P0001 | 409 |
| 23514, 23502, 22001, 22003 | 422 |
| 22P02 | 400 |
| 22023 (estado inválido en los procedimientos existentes) | 409 |
| 40001, 40P01, 55P03, 57014, desconexión o pool agotado | 503, `Retry-After: 1` |

Stock insuficiente es **23514 → 422** en el esquema real. Se conserva esa
correspondencia, aunque el checklist del TPI mencione 409 como ejemplo de venta
sin stock. PostgreSQL 18 también devuelve 23001 para ciertos RESTRICT; se probó
ese caso real y se trata como conflicto. Los RAISE de reglas existentes
conservan solo su mensaje primario útil.

## Pruebas reales

```powershell
.venv/Scripts/python.exe -m pip install -r api/requirements-test.txt
$env:TEST_DB_HOST='127.0.0.1'
$env:TEST_DB_PORT='55441'  # 5432 en una instalación convencional
$env:TEST_DB_ADMIN='postgres'  # Solo preparación y limpieza de pruebas
# TEST_DB_PASSWORD, si corresponde, se configura fuera del repositorio.
.venv/Scripts/python.exe -m pytest api/tests -q --basetemp=.local/pytest_api
```

El administrador debe poder crear bases y roles. Cada ejecución crea
`bodegas_f_test_<uuid>` y `bodegas_f_login_<uuid>`, instala SQL real y fixtures
pequeños, ejecuta HTTP con el login API y elimina únicamente esos dos recursos
generados. No restaura ni vacía una base recibida por entorno. No toca el dataset
de referencia. La base usa los índices actuales, no un modelo alternativo.

La suite verifica catálogo, filtros/paginación, inyección SQL como texto, los
tres subtipos, cambio de subtipo, comprobante válido, histórico conservado,
rollback de venta multirrenglón, composición 80 % rechazada al COMMIT, precio
negativo, duplicado, FK, auditoría, bajas, transferencia válida/sin stock,
ingreso, reprocesamientos, permisos reales, Swagger/OpenAPI y salud tras una
desconexión provocada. Además inicia Uvicorn como proceso y consulta HTTP real.
El resultado y el entorno se conservan en [la evidencia F](../docs/evidencias/fase_f_resultados.json).

## Docker Compose y alcance pendiente

La consigna original pide Compose: copiar `.env.example` a `.env`, reemplazar
las dos contraseñas y ejecutar `docker compose up --build`. Inicializa una base
vacía con `01`–`07`, la función de baja y un login de aplicación sin privilegios
administrativos. No carga automáticamente los cientos de miles de filas C;
los catálogos/datos se cargan por el proceso separado ya aprobado. El bootstrap
solo se ejecuta en un volumen nuevo; no migra volúmenes existentes.

La configuración Compose fue validada, pero el motor Docker Desktop no estaba
disponible en el corte F/G. **En H sí se verificaron los tres contenedores**, con
PostgreSQL/API saludables y frontend/Nginx en `127.0.0.1:8081`. La integración
completa y el respaldo/restauración están en el [informe H](../docs/informe_integracion_final.md).
`DB_SSLMODE` es opcional para ejecución local y se fija a `require` en el perfil
de nube preparado; no se confunde esa configuración con HTTPS público probado.

Fase G está implementada en [frontend/](../frontend/README.md), con filtros,
formularios, estados y errores de negocio probados en navegador. No se implementó
autenticación ni despliegue en nube. El diccionario y la demostración académica de concurrencia
siguen siendo entregables independientes pendientes de las fases anteriores.

Referencias de implementación: [dependencias con yield y scope de FastAPI](https://fastapi.tiangolo.com/tutorial/dependencies/dependencies-with-yield/)
y [transacciones de psycopg](https://www.psycopg.org/psycopg3/docs/basic/transactions.html).
