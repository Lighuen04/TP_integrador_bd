"""Crea y elimina SOLO una base/LOGIN únicos de esta ejecución. Sin mocks SQL."""
import os
import secrets
import uuid
from pathlib import Path

import psycopg
import pytest
from fastapi.testclient import TestClient
from psycopg import sql
from psycopg.rows import dict_row

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture(scope="session")
def entorno():
    # Administración solo para preparar/destruir la base descartable, nunca HTTP.
    host = os.environ.get("TEST_DB_HOST", "127.0.0.1")
    port = os.environ.get("TEST_DB_PORT", "5432")
    admin = dict(host=host, port=port, user=os.environ.get("TEST_DB_ADMIN", "postgres"),
                 password=os.environ.get("TEST_DB_PASSWORD", ""), dbname="postgres", autocommit=True,
                 connect_timeout=5)
    sufijo = uuid.uuid4().hex[:12]
    nombre, usuario = "bodegas_f_test_" + sufijo, "bodegas_f_login_" + sufijo
    password = secrets.token_urlsafe(24)
    with psycopg.connect(**admin) as control:
        control.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(nombre)))
        try:
            with psycopg.connect(**dict(admin, dbname=nombre), row_factory=dict_row) as db:
                for archivo in sorted((ROOT / "database").glob("0[1-7]_*.sql")):
                    db.execute(archivo.read_text(encoding="utf-8"), prepare=False)
                db.execute((ROOT / "database/10_api_baja_vino.sql").read_text(encoding="utf-8"), prepare=False)
                control.execute(sql.SQL("CREATE ROLE {} LOGIN PASSWORD {}").format(
                    sql.Identifier(usuario), sql.Literal(password)))
                control.execute(sql.SQL("GRANT bodegas_api TO {}").format(sql.Identifier(usuario)))
                with db.transaction():
                    db.execute("SET LOCAL ROLE bodegas_propietario")
                    db.execute("SET LOCAL search_path=bodegas_atuel,pg_temp")
                    db.execute("""INSERT INTO localidad VALUES ('5600','San Rafael','Mendoza','Regional');
                        INSERT INTO sala_venta VALUES (1,'Calle','1','domingo','5600');
                        INSERT INTO bodega VALUES ('20200000001','Bodega prueba','Calle');
                        INSERT INTO cepa VALUES (1,'Malbec','tinta');
                        INSERT INTO transportista VALUES ('T1','Transporte','20200000002','t@example.test','1','Calle');
                        INSERT INTO transportista_localidad VALUES ('T1','5600');
                        INSERT INTO vino VALUES ('V1','Vino prueba','tinto',2025,750,13,100,'20200000001');
                        INSERT INTO composicion_vino_cepa VALUES ('V1',1,100);
                        INSERT INTO vino VALUES ('V2','Otro vino','blanco',2024,750,12,200,'20200000001');
                        INSERT INTO composicion_vino_cepa VALUES ('V2',1,100);
                        UPDATE stock_deposito SET cantidad_botellas_disponibles=100 WHERE codigo_vino='V1';
                        INSERT INTO stock_sala VALUES (1,'V1',30),(1,'V2',0);
                        INSERT INTO cliente(id_cliente,nombre,tipo_cliente,tipo_documento,numero_documento,direccion,codigo_postal)
                          VALUES (1,'Socio prueba','socio','DNI','1','Calle','5600');
                        INSERT INTO socio VALUES (1);""", prepare=False)
                anterior = {k: os.environ.get(k) for k in
                            ("DB_HOST", "DB_PORT", "DB_NAME", "DB_USER", "DB_PASSWORD")}
                os.environ.update(DB_HOST=host, DB_PORT=port, DB_NAME=nombre, DB_USER=usuario, DB_PASSWORD=password)
                try:
                    db.execute("SET search_path=bodegas_atuel,pg_temp")
                    yield db, usuario
                finally:
                    for k, v in anterior.items():
                        if v is None:
                            os.environ.pop(k, None)
                        else:
                            os.environ[k] = v
        finally:
            # Identificadores generados aquí; jamás se usa DB_NAME para borrar.
            control.execute(sql.SQL("DROP DATABASE {} WITH (FORCE)").format(sql.Identifier(nombre)))
            control.execute(sql.SQL("DROP ROLE IF EXISTS {}").format(sql.Identifier(usuario)))


@pytest.fixture(scope="session")
def client(entorno):
    from api.main import app
    with TestClient(app, raise_server_exceptions=False) as c:
        yield c


@pytest.fixture
def db(entorno):
    return entorno[0]
