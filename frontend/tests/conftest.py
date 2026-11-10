import os
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

import httpx
import pytest
from playwright.sync_api import sync_playwright

from api.tests.conftest import entorno, db
from frontend.servir import crear_servidor


@pytest.fixture(scope="session")
def web(entorno, tmp_path_factory):
    db, _ = entorno
    with db.transaction():
        db.execute("SET LOCAL ROLE bodegas_propietario")
        for n in range(2, 27):
            db.execute("""INSERT INTO cliente(id_cliente,nombre,tipo_cliente,tipo_documento,numero_documento,direccion,codigo_postal)
                VALUES (%s,'Cliente de prueba','socio','DNI',%s,'Calle','5600')""", (n, str(n)))
            db.execute("INSERT INTO socio VALUES (%s)", (n,))
        for n in range(1, 24):
            name = f"Etiqueta de prueba {n:02}" if n != 23 else '<img src=x onerror="window.xss=true">'
            db.execute("""INSERT INTO vino(codigo_vino,nombre_comercial,tipo,anada,presentacion_ml,graduacion_alcoholica,precio,cuit_bodega)
                VALUES (%s,%s,'tinto',2026,750,13,100,'20200000001')""", (f"UI{n:02}", name))
            db.execute("INSERT INTO composicion_vino_cepa VALUES (%s,1,100)", (f"UI{n:02}",))
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0)); api_port = sock.getsockname()[1]
    artifact = tmp_path_factory.mktemp("web")
    with (artifact / "uvicorn.log").open("w", encoding="utf-8") as log:
        process = subprocess.Popen([sys.executable,"-m","uvicorn","api.main:app","--host","127.0.0.1","--port",str(api_port)], stdout=log, stderr=log)
        proxy = crear_servidor(puerto=0, api=f"http://127.0.0.1:{api_port}")
        thread = threading.Thread(target=proxy.serve_forever, daemon=True); thread.start()
        try:
            with httpx.Client(trust_env=False, timeout=2) as http:
                for _ in range(70):
                    try:
                        if http.get(f"http://127.0.0.1:{api_port}/salud").status_code == 200:
                            break
                    except httpx.ConnectError:
                        pass
                    time.sleep(.1)
                else:
                    pytest.fail("La API real no inició")
                for path in ("/salud", "/vinos", "/docs", "/openapi.json"):
                    assert http.get(f"http://127.0.0.1:{api_port}" + path).status_code == 200
                    # Rutas originales utilizadas por Swagger a través del proxy.
                    assert http.get(f"http://127.0.0.1:{proxy.server_port}" + path).status_code == 200
            yield f"http://127.0.0.1:{proxy.server_port}", process
        finally:
            if process.poll() is None:
                process.terminate(); process.wait(timeout=10)
            proxy.shutdown(); thread.join(timeout=5); proxy.server_close()


@pytest.fixture(scope="session")
def browser():
    with sync_playwright() as playwright:
        channel = os.environ.get("UI_BROWSER_CHANNEL")
        browser = playwright.chromium.launch(channel=channel, headless=True)
        yield browser
        browser.close()


@pytest.fixture
def page(browser, web):
    context = browser.new_context(viewport={"width":1440,"height":1000}, locale="es-AR")
    page = context.new_page()
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.goto(web[0])
    page.wait_for_selector('#salud[data-estado="ok"]:not([disabled])')
    page.wait_for_selector('#vinos-body tr')
    yield page
    assert not errors, errors
    context.close()
