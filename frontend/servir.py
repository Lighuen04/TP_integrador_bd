"""Servidor local sin dependencias: estáticos + proxy de mismo origen (no producción)."""
import argparse
import json
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import ProxyHandler, Request, build_opener


def crear_servidor(host="127.0.0.1", puerto=8081, api="http://127.0.0.1:8000"):
    class Handler(SimpleHTTPRequestHandler):
        def handle_request(self):
            # Igual que Nginx: un archivo estático existente se sirve aquí;
            # el resto pasa a la API, incluidas las rutas originales de Swagger.
            static = Path(self.translate_path(self.path)).exists()
            if static and not (self.path.startswith("/api/") or self.path.split("?")[0] in {"/docs", "/openapi.json"}):
                if self.command == "GET":
                    return super().do_GET()
                self.send_error(405)
                return
            path = self.path[4:] if self.path.startswith("/api/") else self.path
            data = self.rfile.read(int(self.headers.get("Content-Length", 0))) if self.command in {"POST", "PUT"} else None
            headers = {"Accept": "application/json", "Content-Type": "application/json"}
            upstream = Request(api.rstrip("/") + path, data=data, headers=headers, method=self.command)
            try:
                result = build_opener(ProxyHandler({})).open(upstream, timeout=25)
            except HTTPError as error:
                result = error
            except (URLError, TimeoutError, OSError):
                body = json.dumps({"detalle": "La API no está disponible. Verificá el servicio e intentá nuevamente.", "sqlstate": None}).encode()
                self.send_response(503); self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
                return
            with result:
                body = result.read()
                self.send_response(result.status)
                for name in ("Content-Type", "Retry-After"):
                    if result.headers.get(name):
                        self.send_header(name, result.headers[name])
                self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

        do_GET = do_POST = do_PUT = do_DELETE = handle_request

    return ThreadingHTTPServer((host, puerto), partial(Handler, directory=str(Path(__file__).resolve().parent)))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--puerto", type=int, default=8081)
    parser.add_argument("--api", default="http://127.0.0.1:8000")
    args = parser.parse_args()
    with crear_servidor(puerto=args.puerto, api=args.api) as server:
        print(f"Frontend: http://127.0.0.1:{args.puerto}", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
