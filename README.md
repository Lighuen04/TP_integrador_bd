# repo_trabajo_final

Proyecto TPI Bodegas del Atuel, PostgreSQL y API REST con SQL directo.

- [Instalación y reglas de la base](database/README.md).
- [Carga reproducible](database/seed/README.md).
- [Índices y mediciones](docs/informe_rendimiento_indices.md).
- [API REST: instalación, rutas y pruebas](api/README.md).
- [Frontend: pantallas, integración y ejecución](frontend/README.md).

La API se ejecuta con `python -m uvicorn api.main:app` después de instalar
`api/requirements.txt` y configurar las variables DB_* indicadas en su README.
Swagger queda en `/docs`.

Para iniciar también el frontend local: `python frontend/servir.py` en otra
terminal y abrir `http://127.0.0.1:8080`. Con Docker Desktop disponible,
configurar `.env` desde `.env.example` y ejecutar `docker compose up --build`.
Compose incluye PostgreSQL, API y frontend; su arranque todavía no se verificó
porque el motor Docker no estaba disponible. La integración local sí se probó.
