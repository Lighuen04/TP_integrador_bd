from decimal import Decimal

import psycopg
import pytest


def vino(codigo="NUEVO", porcentaje=100, precio=100):
    return dict(codigo_vino=codigo, nombre_comercial=codigo, tipo="tinto", anada=2026,
                presentacion_ml=750, graduacion_alcoholica=13, precio=precio,
                cuit_bodega="20200000001", composicion=[dict(id_cepa=1, porcentaje_corte=porcentaje)])


def cliente(identificador=10, tipo="socio", **cambios):
    return dict(id_cliente=identificador, nombre="Cliente", tipo_cliente=tipo,
                tipo_documento="DNI", numero_documento=str(identificador),
                direccion="Calle", codigo_postal="5600", **cambios)


def venta(numero, renglones=None):
    return dict(numero_comprobante=numero, id_cliente=1, id_sala=1,
                renglones=renglones or [dict(codigo_vino="V1", cantidad=2)])


def test_listado_y_detalle(client):
    assert client.get("/vinos").status_code == 200
    ficha = client.get("/vinos/V1").json()
    assert ficha["composicion"][0]["porcentaje_corte"] == 100
    assert "maridajes" in ficha
    assert client.get("/vinos/inexistente").status_code == 404


def test_filtros_paginacion_e_inyeccion(client, db):
    r = client.get("/vinos", params=dict(tipo="tinto", cepa=1, bodega="20200000001", anada=2025, limite=1))
    assert [v["codigo_vino"] for v in r.json()] == ["V1"]
    assert client.get("/vinos", params=dict(limite=1, offset=1)).json()[0]["codigo_vino"] == "V2"
    assert client.get("/vinos", params=dict(tipo="tinto'; DROP TABLE vino; --")).json() == []
    assert db.execute("SELECT count(*) AS n FROM vino").fetchone()["n"] == 2
    assert client.get("/vinos?limite=101").status_code == 422


@pytest.mark.parametrize("identificador,tipo,extra", [(10,"socio",{}),
    (11,"distribuidor",dict(zona_cobertura="Sur",numero_habilitacion="H1")),
    (12,"exportador",dict(pais_destino="Chile"))])
def test_alta_cliente_tres_subtipos(client, db, identificador, tipo, extra):
    r = client.post("/clientes", json=cliente(identificador, tipo, **extra))
    assert r.status_code == 201, r.text
    assert Decimal(str(r.json()["descuento"])) == {"socio":10,"distribuidor":20,"exportador":30}[tipo]
    assert client.get(f"/clientes/{identificador}").status_code == 200
    n = db.execute("""SELECT (SELECT count(*) FROM socio WHERE id_cliente=%s)+
        (SELECT count(*) FROM distribuidor WHERE id_cliente=%s)+
        (SELECT count(*) FROM exportador WHERE id_cliente=%s) AS n""", (identificador,)*3).fetchone()["n"]
    assert n == 1


def test_cliente_invalido_db_sin_parciales(client, db):
    r = client.post("/clientes", json=cliente(13,"distribuidor"))
    assert r.status_code == 422 and r.json()["sqlstate"] == "23502"
    assert db.execute("SELECT * FROM cliente WHERE id_cliente=13").fetchone() is None
    p = cliente(14); p["nombre"] = " "
    r = client.post("/clientes", json=p)
    assert r.status_code == 422 and r.json()["sqlstate"] == "23514"


def test_cambiar_subtipo_y_baja(client, db):
    p = cliente(15)
    assert client.post("/clientes", json=p).status_code == 201
    p.pop("id_cliente"); p.update(tipo_cliente="exportador",pais_destino="Chile")
    r = client.put("/clientes/15", json=p)
    assert r.status_code == 200 and Decimal(r.json()["descuento"]) == 30
    assert db.execute("SELECT * FROM socio WHERE id_cliente=15").fetchone() is None
    assert client.delete("/clientes/15").status_code == 204
    assert client.get("/clientes/15").status_code == 404


def test_venta_valida_historica(client, db):
    antes = db.execute("SELECT cantidad_stock FROM stock_sala WHERE id_sala=1 AND codigo_vino='V1'").fetchone()["cantidad_stock"]
    r = client.post("/comprobantes", json=venta("C1"))
    assert r.status_code == 201, r.text
    assert Decimal(r.json()["total"]) == 180 and Decimal(r.json()["descuento_aplicado"]) == 10
    assert Decimal(r.json()["renglones"][0]["precio"]) == 100
    assert client.get("/comprobantes/C1").json() == r.json()
    assert db.execute("SELECT cantidad_stock FROM stock_sala WHERE id_sala=1 AND codigo_vino='V1'").fetchone()["cantidad_stock"] == antes-2
    # Cambiar subtipo/descuento actual no altera la venta ya emitida.
    p = cliente(1,"distribuidor",zona_cobertura="Sur",numero_habilitacion="H2"); p.pop("id_cliente")
    assert client.put("/clientes/1", json=p).status_code == 200
    assert Decimal(client.get("/comprobantes/C1").json()["total"]) == 180
    p = cliente(1); p.pop("id_cliente")
    assert client.put("/clientes/1", json=p).status_code == 200


def test_venta_fallida_revierte_todos_los_renglones(client, db):
    antes = db.execute("SELECT * FROM stock_sala ORDER BY id_sala,codigo_vino").fetchall()
    r = client.post("/comprobantes", json=venta("FALLA", [dict(codigo_vino="V1",cantidad=1), dict(codigo_vino="V2",cantidad=1)]))
    assert r.status_code == 422 and r.json()["sqlstate"] == "23514"
    assert "Stock insuficiente" in r.json()["detalle"]
    assert db.execute("SELECT * FROM comprobante WHERE numero_comprobante='FALLA'").fetchone() is None
    assert db.execute("SELECT * FROM comprobante_vino WHERE numero_comprobante='FALLA'").fetchone() is None
    assert db.execute("SELECT * FROM stock_sala ORDER BY id_sala,codigo_vino").fetchall() == antes


def test_precio_y_descuento_externos_rechazados(client):
    p = venta("MANIPULADO"); p["descuento_aplicado"] = 100
    assert client.post("/comprobantes", json=p).status_code == 422
    p.pop("descuento_aplicado"); p["renglones"][0]["precio"] = 1
    assert client.post("/comprobantes", json=p).status_code == 422


def test_composicion_diferida_80_rollback_commit(client, db):
    r = client.post("/vinos", json=vino("CORTE80", 80))
    assert r.status_code == 422, r.text
    assert r.json()["sqlstate"] == "23514"
    for tabla in ("vino", "stock_deposito", "composicion_vino_cepa"):
        assert db.execute(f"SELECT * FROM {tabla} WHERE codigo_vino='CORTE80'").fetchone() is None
    assert client.get("/salud").status_code == 200


def test_vino_crud_auditoria_y_baja_fk(client, db, entorno):
    p = vino("BAJA")
    assert client.post("/vinos", json=p).status_code == 201
    assert client.delete("/vinos/BAJA").status_code == 204
    assert db.execute("SELECT * FROM stock_deposito WHERE codigo_vino='BAJA'").fetchone() is None
    p = vino("AUDITA")
    assert client.post("/vinos", json=p).status_code == 201
    p.pop("codigo_vino"); p["precio"] = 110
    assert client.put("/vinos/AUDITA", json=p).status_code == 200
    a = db.execute("SELECT * FROM auditoria_precios WHERE codigo_vino='AUDITA'").fetchone()
    assert a["precio_anterior"] == 100 and a["precio_nuevo"] == 110
    assert a["usuario_modificacion"] == entorno[1]
    r = client.delete("/vinos/AUDITA")
    assert r.status_code == 409 and r.json()["sqlstate"] in {"23503", "23001"}
    assert client.get("/vinos/AUDITA").json()["composicion"]
    assert db.execute("SELECT * FROM stock_deposito WHERE codigo_vino='AUDITA'").fetchone() is not None


def test_precio_negativo_y_duplicado_fk(client):
    r = client.post("/vinos", json=vino("NEG", precio=-1))
    assert r.status_code == 422 and r.json()["sqlstate"] == "23514"
    r = client.post("/vinos", json=vino("V1"))
    assert r.status_code == 409 and r.json()["sqlstate"] == "23505"
    p = vino("FK"); p["cuit_bodega"] = "20999999999"
    r = client.post("/vinos", json=p)
    assert r.status_code == 409 and r.json()["sqlstate"] == "23503"


def test_transferencia_completa_y_reprocesamiento(client, db):
    d = db.execute("SELECT cantidad_botellas_disponibles AS n FROM stock_deposito WHERE codigo_vino='V1'").fetchone()["n"]
    s = db.execute("SELECT cantidad_stock AS n FROM stock_sala WHERE codigo_vino='V1' AND id_sala=1").fetchone()["n"]
    assert client.post("/transferencias", json=dict(numero_solicitud="T-OK",id_sala=1)).status_code == 201
    assert client.post("/transferencias/T-OK/renglones", json=dict(codigo_vino="V1",cantidad_botellas=5)).status_code == 201
    assert client.post("/transferencias/T-OK/terminar").json()["estado"] == "terminado"
    assert client.post("/transferencias/T-OK/procesar").json()["estado"] == "procesado"
    r = client.post("/transferencias/T-OK/procesar")
    assert r.status_code == 409 and r.json()["sqlstate"] == "22023"
    assert db.execute("SELECT cantidad_botellas_disponibles AS n FROM stock_deposito WHERE codigo_vino='V1'").fetchone()["n"] == d-5
    assert db.execute("SELECT cantidad_stock AS n FROM stock_sala WHERE codigo_vino='V1' AND id_sala=1").fetchone()["n"] == s+5
    r = client.post("/transferencias/T-OK/renglones", json=dict(codigo_vino="V2",cantidad_botellas=1))
    assert r.status_code == 422 and r.json()["sqlstate"] == "23514"


def test_transferencia_sin_stock_atomica(client, db):
    antes = db.execute("SELECT * FROM stock_deposito ORDER BY codigo_vino").fetchall()
    salas = db.execute("SELECT * FROM stock_sala ORDER BY id_sala,codigo_vino").fetchall()
    assert client.post("/transferencias", json=dict(numero_solicitud="T-NO",id_sala=1)).status_code == 201
    for codigo in ("V1", "V2"):
        assert client.post("/transferencias/T-NO/renglones", json=dict(codigo_vino=codigo,cantidad_botellas=1)).status_code == 201
    assert client.post("/transferencias/T-NO/terminar").status_code == 200
    r = client.post("/transferencias/T-NO/procesar")
    assert r.status_code == 422 and r.json()["sqlstate"] == "23514", r.text
    assert db.execute("SELECT estado FROM transferencia WHERE numero_solicitud='T-NO'").fetchone()["estado"] == "terminado"
    assert db.execute("SELECT * FROM stock_deposito ORDER BY codigo_vino").fetchall() == antes
    assert db.execute("SELECT * FROM stock_sala ORDER BY id_sala,codigo_vino").fetchall() == salas


def test_ingreso_procesado_una_vez(client, db):
    n = db.execute("SELECT cantidad_botellas_disponibles AS n FROM stock_deposito WHERE codigo_vino='V1'").fetchone()["n"]
    assert client.post("/ingresos", json=dict(codigo_ingreso="I-OK",codigo_transporte="T1",cuit_bodega="20200000001")).status_code == 201
    assert client.post("/ingresos/I-OK/renglones", json=dict(codigo_vino="V1",cantidad_botellas=7)).status_code == 201
    r = client.post("/ingresos/I-OK/procesar")
    assert r.status_code == 409 and r.json()["sqlstate"] == "22023"
    assert client.post("/ingresos/I-OK/terminar").status_code == 200
    assert client.post("/ingresos/I-OK/procesar").status_code == 200
    assert client.post("/ingresos/I-OK/procesar").status_code == 409
    assert db.execute("SELECT cantidad_botellas_disponibles AS n FROM stock_deposito WHERE codigo_vino='V1'").fetchone()["n"] == n+7


def test_salud_openapi_reportes(client):
    assert client.get("/salud").json() == {"api":"ok","postgresql":"ok"}
    spec = client.get("/openapi.json").json()
    assert len(spec["paths"]) == 20
    assert "409" in spec["paths"]["/comprobantes"]["post"]["responses"]
    for ruta in ("top-vinos","ventas-por-sala","vinos-sin-stock?sala=1","transportista-activo","trazabilidad/V1"):
        assert client.get("/reportes/" + ruta).status_code == 200


def test_permisos_reales_rol_api(client, entorno):
    import os
    with psycopg.connect(host=os.environ["DB_HOST"],port=os.environ["DB_PORT"],
        dbname=os.environ["DB_NAME"],user=os.environ["DB_USER"],password=os.environ["DB_PASSWORD"], autocommit=True) as c:
        assert c.execute("SELECT current_user").fetchone()[0] == entorno[1]
        for sentencia in ("UPDATE bodegas_atuel.stock_sala SET cantidad_stock=999",
                          "DELETE FROM bodegas_atuel.stock_deposito",
                          "UPDATE bodegas_atuel.comprobante SET total=0",
                          "CREATE TABLE bodegas_atuel.prohibido(id int)",
                          "SET ROLE bodegas_propietario"):
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                c.execute(sentencia)


def test_baja_impide_perder_stock_y_venta(client, db):
    assert client.post("/comprobantes", json=venta("VENTA-BAJA")).status_code == 201
    antes = db.execute("SELECT * FROM stock_deposito WHERE codigo_vino='V1'").fetchone()
    r = client.delete("/vinos/V1")
    assert r.status_code == 409 and r.json()["sqlstate"] in {"23001", "23503"}
    assert db.execute("SELECT * FROM stock_deposito WHERE codigo_vino='V1'").fetchone() == antes
    assert client.get("/vinos/V1").json()["composicion"]
    r = client.delete("/clientes/1")
    assert r.status_code == 409 and r.json()["sqlstate"] in {"23001", "23503"}


def test_uvicorn_http_real(client, entorno, tmp_path):
    import socket
    import subprocess
    import sys
    import time
    import httpx

    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    with (tmp_path / "uvicorn.log").open("w", encoding="utf-8") as log:
        proceso = subprocess.Popen([sys.executable,"-m","uvicorn","api.main:app",
            "--host","127.0.0.1","--port",str(port)], stdout=log, stderr=log)
        try:
            with httpx.Client(base_url=f"http://127.0.0.1:{port}",timeout=2,trust_env=False) as http:
                for _ in range(50):
                    if proceso.poll() is not None:
                        pytest.fail("Uvicorn terminó antes de aceptar conexiones")
                    try:
                        respuesta = http.get("/salud")
                        break
                    except httpx.ConnectError:
                        time.sleep(0.1)
                else:
                    pytest.fail("Uvicorn no respondió en cinco segundos")
                assert respuesta.status_code == 200
                assert http.get("/vinos?limite=1").status_code == 200
                assert http.get("/docs").status_code == 200
                assert http.get("/openapi.json").status_code == 200
        finally:
            proceso.terminate()
            proceso.wait(timeout=10)


def test_salud_conexion_interrumpida_503(client, db, entorno):
    # Caída real de las conexiones de esta cuenta de prueba; el pool debe
    # traducirla a 503 y recuperar una conexión nueva, sin trazas públicas.
    db.execute("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename=%s", (entorno[1],)).fetchall()
    r = client.get("/salud")
    assert r.status_code == 503, r.text
    assert "Traceback" not in r.text and "password" not in r.text
    assert client.get("/salud").status_code == 200
