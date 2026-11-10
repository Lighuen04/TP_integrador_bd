# repo_trabajo_final

Proyecto TPI Bodegas del Atuel, PostgreSQL y API REST con SQL directo.

- [Instalación y reglas de la base](database/README.md).
- [Carga reproducible](database/seed/README.md).
- [Índices y mediciones](docs/informe_rendimiento_indices.md).
- [API REST: instalación, rutas y pruebas](api/README.md).

La API se ejecuta con `python -m uvicorn api.main:app` después de instalar
`api/requirements.txt` y configurar las variables DB_* indicadas en su README.
Swagger queda en `/docs`. El frontend corresponde a la próxima fase G.
