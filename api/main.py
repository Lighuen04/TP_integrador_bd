from typing import Annotated, Optional

import psycopg
from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from psycopg_pool import PoolTimeout

from . import repository as repo, schemas as s
from .database import conexion, lifespan

ERRORS = {400: {"model": s.Error}, 404: {"model": s.Error},
          409: {"model": s.Error}, 422: {"model": s.Error},
          503: {"model": s.Error}}
app = FastAPI(title="Bodegas del Atuel", version="1.0.0", lifespan=lifespan,
              responses=ERRORS)
# Importante: los triggers diferidos deben ejecutarse ANTES de enviar el éxito.
DB = Annotated[psycopg.Connection, Depends(conexion, scope="function")]
Limite = Annotated[int, Query(ge=1, le=100, description="Máximo de filas")]
Offset = Annotated[int, Query(ge=0, description="Filas a omitir")]


@app.exception_handler(psycopg.Error)
async def error_pg(request: Request, exc: psycopg.Error):
    estado = exc.sqlstate
    status = {"23505": 409, "23503": 409, "23001": 409, "23514": 422, "23502": 422,
              "P0001": 409, "22P02": 400, "22001": 422, "22003": 422,
              "22023": 409, "40001": 503, "40P01": 503,
              "55P03": 503, "57014": 503}.get(estado, 500)
    if (isinstance(exc, psycopg.OperationalError) and estado is None
            or estado and (estado.startswith("08") or estado in {"57P01", "57P02", "57P03"})):
        status = 503
    mensajes = {"23505": "Ya existe un registro con esa clave o dato único.",
                "23503": "Falta un registro relacionado o existen dependencias que impiden la operación.",
                "23001": "Existen dependencias que impiden eliminar el registro (RESTRICT).",
                "23514": "El dato no cumple una restricción de la base de datos.",
                "23502": "Falta un dato obligatorio para el registro o su subtipo.",
                "22P02": "Formato de dato inválido.", "22001": "Texto demasiado largo.",
                "22003": "Número fuera del rango admitido."}
    detalle = mensajes.get(estado, "No se pudo completar la operación.")
    # RAISE de nuestras reglas: solo mensaje primario; nunca DETAIL/CONTEXT/SQL.
    if estado in {"23514", "23503", "22023", "P0001"} and not exc.diag.constraint_name:
        detalle = exc.diag.message_primary or detalle
    if status == 503:
        detalle = "Base no disponible o conflicto transitorio. Reintentar la operación completa."
    return JSONResponse(status_code=status, content={"detalle": detalle, "sqlstate": estado},
                        headers={"Retry-After": "1"} if status == 503 else None)


@app.exception_handler(PoolTimeout)
async def error_pool(request: Request, exc: PoolTimeout):
    return JSONResponse(status_code=503, content={"detalle": "Base de datos no disponible.", "sqlstate": None},
                        headers={"Retry-After": "1"})


@app.exception_handler(HTTPException)
async def error_http(request: Request, exc: HTTPException):
    return JSONResponse(status_code=exc.status_code, content={"detalle": exc.detail, "sqlstate": None})


@app.exception_handler(RequestValidationError)
async def error_formato(request: Request, exc: RequestValidationError):
    detalle = "; ".join(".".join(map(str, e["loc"])) + ": " + e["msg"] for e in exc.errors())
    return JSONResponse(status_code=422, content={"detalle": detalle, "sqlstate": None})


@app.get("/salud", tags=["Salud"])
def salud(db: DB):
    db.execute("SELECT 1")
    return {"api": "ok", "postgresql": "ok"}


@app.get("/vinos", tags=["Vinos"], response_model=list[s.VinoSalida])
def vinos(db: DB, limite: Limite = 20, offset: Offset = 0,
          tipo: Optional[str] = None, cepa: Optional[int] = None,
          bodega: Optional[str] = None, anada: Optional[int] = None):
    return repo.vinos(db, limite, offset, tipo, cepa, bodega, anada)


@app.get("/vinos/{codigo}", tags=["Vinos"], response_model=s.VinoDetalle)
def vino(codigo: str, db: DB):
    return repo.vino(db, codigo)


@app.post("/vinos", status_code=201, tags=["Vinos"], response_model=s.VinoDetalle)
def crear_vino(pedido: s.VinoNuevo, db: DB):
    return repo.guardar_vino(db, pedido.codigo_vino, pedido, True)


@app.put("/vinos/{codigo}", tags=["Vinos"], response_model=s.VinoDetalle)
def modificar_vino(codigo: str, pedido: s.Vino, db: DB):
    return repo.guardar_vino(db, codigo, pedido, False)


@app.delete("/vinos/{codigo}", status_code=204, tags=["Vinos"])
def borrar_vino(codigo: str, db: DB):
    repo.borrar_vino(db, codigo)
    return Response(status_code=204)


@app.get("/clientes", tags=["Clientes"], response_model=list[s.ClienteSalida])
def clientes(db: DB, limite: Limite = 20, offset: Offset = 0):
    return repo.clientes(db, limite, offset)


@app.get("/clientes/{identificador}", tags=["Clientes"], response_model=s.ClienteSalida)
def cliente(identificador: int, db: DB):
    return repo.cliente(db, identificador)


@app.post("/clientes", status_code=201, tags=["Clientes"], response_model=s.ClienteSalida)
def crear_cliente(pedido: s.ClienteNuevo, db: DB):
    return repo.guardar_cliente(db, pedido.id_cliente, pedido, True)


@app.put("/clientes/{identificador}", tags=["Clientes"], response_model=s.ClienteSalida)
def modificar_cliente(identificador: int, pedido: s.Cliente, db: DB):
    return repo.guardar_cliente(db, identificador, pedido, False)


@app.delete("/clientes/{identificador}", status_code=204, tags=["Clientes"])
def borrar_cliente(identificador: int, db: DB):
    repo.borrar_cliente(db, identificador)
    return Response(status_code=204)


@app.post("/comprobantes", status_code=201, tags=["Comprobantes"], response_model=s.ComprobanteSalida)
def crear_comprobante(pedido: s.Comprobante, db: DB):
    return repo.crear_comprobante(db, pedido)


@app.get("/comprobantes/{numero}", tags=["Comprobantes"], response_model=s.ComprobanteSalida)
def comprobante(numero: str, db: DB):
    return repo.comprobante(db, numero)


@app.post("/transferencias", status_code=201, tags=["Transferencias"])
def crear_transferencia(pedido: s.Transferencia, db: DB):
    return repo.crear_documento(db, "transferencias", pedido)


@app.post("/transferencias/{numero}/renglones", status_code=201, tags=["Transferencias"])
def renglon_transferencia(numero: str, pedido: s.Renglon, db: DB):
    return repo.agregar_renglon(db, "transferencias", numero, pedido)


@app.post("/transferencias/{numero}/terminar", tags=["Transferencias"])
def terminar_transferencia(numero: str, db: DB):
    return repo.cambiar_estado(db, "transferencias", numero, False)


@app.post("/transferencias/{numero}/procesar", tags=["Transferencias"])
def procesar_transferencia(numero: str, db: DB):
    return repo.cambiar_estado(db, "transferencias", numero, True)


@app.post("/ingresos", status_code=201, tags=["Ingresos"])
def crear_ingreso(pedido: s.Ingreso, db: DB):
    return repo.crear_documento(db, "ingresos", pedido)


@app.post("/ingresos/{codigo}/renglones", status_code=201, tags=["Ingresos"])
def renglon_ingreso(codigo: str, pedido: s.Renglon, db: DB):
    return repo.agregar_renglon(db, "ingresos", codigo, pedido)


@app.post("/ingresos/{codigo}/terminar", tags=["Ingresos"])
def terminar_ingreso(codigo: str, db: DB):
    return repo.cambiar_estado(db, "ingresos", codigo, False)


@app.post("/ingresos/{codigo}/procesar", tags=["Ingresos"])
def procesar_ingreso(codigo: str, db: DB):
    return repo.cambiar_estado(db, "ingresos", codigo, True)


@app.get("/reportes/top-vinos", tags=["Reportes"])
def top_vinos(db: DB):
    return repo.top_vinos(db)


@app.get("/reportes/ventas-por-sala", tags=["Reportes"])
def ventas_sala(db: DB):
    return repo.ventas_sala(db)


@app.get("/reportes/vinos-sin-stock", tags=["Reportes"])
def sin_stock(db: DB, sala: int = Query(description="Sala cuyo stock se consulta")):
    return repo.sin_stock(db, sala)


@app.get("/reportes/transportista-activo", tags=["Reportes"])
def transportista_activo(db: DB):
    return repo.transportista_activo(db)


@app.get("/reportes/trazabilidad/{codigo}", tags=["Reportes"])
def trazabilidad(codigo: str, db: DB):
    return repo.trazabilidad(db, codigo)
