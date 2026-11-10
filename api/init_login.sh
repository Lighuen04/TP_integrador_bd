#!/bin/sh
set -eu
# Solo bootstrap: psql cita identificadores/literales; no concatena SQL en shell.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  --set=app_user="$DB_USER" --set=app_password="$DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'app_user', :'app_password') \gexec
SELECT format('GRANT bodegas_api TO %I', :'app_user') \gexec
SQL
