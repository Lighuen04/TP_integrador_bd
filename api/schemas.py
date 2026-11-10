"""Forma de los pedidos. Las reglas de negocio se validan en PostgreSQL."""
from datetime import date
from decimal import Decimal
from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field


class Entrada(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Corte(Entrada):
    id_cepa: int
    porcentaje_corte: Decimal


class DatosVino(Entrada):
    nombre_comercial: str = Field(max_length=160)
    tipo: str = Field(max_length=24)
    anada: int
    presentacion_ml: int
    graduacion_alcoholica: Decimal
    precio: Decimal
    cuit_bodega: str = Field(max_length=11)


class Vino(DatosVino):
    composicion: list[Corte]


class VinoNuevo(Vino):
    codigo_vino: str = Field(min_length=1, max_length=40)


class Cliente(Entrada):
    apellido: Optional[str] = Field(default=None, max_length=120)
    nombre: str = Field(max_length=160)
    tipo_cliente: Literal["socio", "distribuidor", "exportador"]
    tipo_documento: str = Field(max_length=32)
    numero_documento: str = Field(max_length=40)
    direccion: str = Field(max_length=240)
    codigo_postal: str = Field(max_length=16)
    zona_cobertura: Optional[str] = Field(default=None, max_length=160)
    numero_habilitacion: Optional[str] = Field(default=None, max_length=64)
    pais_destino: Optional[str] = Field(default=None, max_length=120)


class ClienteNuevo(Cliente):
    id_cliente: int


class RenglonVenta(Entrada):
    codigo_vino: str = Field(min_length=1, max_length=40)
    cantidad: int


class Comprobante(Entrada):
    numero_comprobante: str = Field(min_length=1, max_length=40)
    fecha: date = Field(default_factory=date.today)
    id_cliente: int
    id_sala: int
    renglones: list[RenglonVenta] = Field(min_length=1)


class Transferencia(Entrada):
    numero_solicitud: str = Field(min_length=1, max_length=40)
    id_sala: int


class Ingreso(Entrada):
    codigo_ingreso: str = Field(min_length=1, max_length=40)
    fecha: date = Field(default_factory=date.today)
    codigo_transporte: str = Field(max_length=40)
    cuit_bodega: str = Field(max_length=11)


class Renglon(Entrada):
    codigo_vino: str = Field(min_length=1, max_length=40)
    cantidad_botellas: int


class Error(BaseModel):
    detalle: str
    sqlstate: Optional[str] = None


class VinoSalida(DatosVino):
    codigo_vino: str


class VinoDetalle(VinoSalida):
    bodega: str
    composicion: list[dict]
    maridajes: list[dict]
    stock_total: int


class ClienteSalida(Cliente):
    id_cliente: int
    descuento: Decimal
    fecha_de_alta: date


class RenglonVentaSalida(RenglonVenta):
    numero_comprobante: str
    precio: Decimal


class ComprobanteSalida(Entrada):
    numero_comprobante: str
    fecha: date
    id_cliente: int
    id_sala: int
    descuento_aplicado: Decimal
    total: Decimal
    renglones: list[RenglonVentaSalida]
