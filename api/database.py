"""Pool por aplicación y transacción por petición, confirmada antes del HTTP."""
import os
from contextlib import asynccontextmanager

from fastapi import Request
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool


@asynccontextmanager
async def lifespan(app):
    kwargs = {key: os.environ[name] for key, name in (
        ("host", "DB_HOST"), ("port", "DB_PORT"), ("dbname", "DB_NAME"),
        ("user", "DB_USER"), ("password", "DB_PASSWORD"))}
    if kwargs["user"] in {"postgres", "bodegas_propietario"}:
        raise RuntimeError("Configurar una cuenta de acceso del rol bodegas_api.")
    kwargs.update(row_factory=dict_row, autocommit=True, connect_timeout=3,
                  options="-csearch_path=bodegas_atuel,pg_temp -cstatement_timeout=15000 -clock_timeout=5000")
    # Para la configuración de nube con TLS o un PostgreSQL remoto.
    if os.environ.get("DB_SSLMODE"):
        kwargs["sslmode"] = os.environ["DB_SSLMODE"]
    if os.environ.get("DB_SSLROOTCERT"):
        kwargs["sslrootcert"] = os.environ["DB_SSLROOTCERT"]
    pool = ConnectionPool(kwargs=kwargs, min_size=1, max_size=5, timeout=5,
                          open=False, name="bodegas-api")
    app.state.pool = pool
    pool.open()
    try:
        pool.wait(timeout=10)
        with pool.connection() as conn:
            role = conn.execute("""SELECT current_user AS usuario,
                r.rolsuper, r.rolcreatedb, r.rolcreaterole,
                pg_has_role(current_user,'bodegas_api','MEMBER') AS api,
                pg_has_role(current_user,'bodegas_propietario','MEMBER') AS propietario,
                has_schema_privilege(current_user,'bodegas_atuel','CREATE') AS crea
                FROM pg_roles r WHERE rolname=current_user""").fetchone()
            if (not role["api"] or any(role[k] for k in
                    ("rolsuper", "rolcreatedb", "rolcreaterole", "propietario", "crea"))):
                raise RuntimeError("La cuenta debe pertenecer solo al rol API sin privilegios administrativos.")
        yield
    finally:
        pool.close()


def conexion(request: Request):
    with request.app.state.pool.connection() as conn:
        # transaction() emite BEGIN y COMMIT/ROLLBACK incluso en autocommit.
        with conn.transaction():
            yield conn
