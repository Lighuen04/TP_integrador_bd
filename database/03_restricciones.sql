-- Roles grupales sin contraseña. La cuenta de acceso de cada entorno debe
-- recibir membresía por un administrador, fuera de estos scripts.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bodegas_propietario') THEN
    CREATE ROLE bodegas_propietario NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bodegas_api') THEN
    CREATE ROLE bodegas_api NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bodegas_reportes') THEN
    CREATE ROLE bodegas_reportes NOLOGIN;
  END IF;
END;
$$;

REVOKE ALL ON SCHEMA bodegas_atuel FROM PUBLIC;
GRANT USAGE ON SCHEMA bodegas_atuel
  TO bodegas_propietario, bodegas_api, bodegas_reportes;
GRANT CREATE ON SCHEMA bodegas_atuel TO bodegas_propietario;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA bodegas_atuel
  TO bodegas_propietario;
GRANT SELECT, INSERT, DELETE ON ALL TABLES IN SCHEMA bodegas_atuel
  TO bodegas_api;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA bodegas_atuel
  TO bodegas_propietario;

GRANT UPDATE ON
  bodegas_atuel.localidad,
  bodegas_atuel.sala_venta,
  bodegas_atuel.empleado,
  bodegas_atuel.finca,
  bodegas_atuel.cepa,
  bodegas_atuel.parcela,
  bodegas_atuel.lote_uva,
  bodegas_atuel.analisis_calidad,
  bodegas_atuel.bodega,
  bodegas_atuel.vino,
  bodegas_atuel.composicion_vino_cepa,
  bodegas_atuel.maridaje,
  bodegas_atuel.vino_maridaje,
  bodegas_atuel.cliente,
  bodegas_atuel.socio,
  bodegas_atuel.distribuidor,
  bodegas_atuel.exportador,
  bodegas_atuel.permiso_exportacion,
  bodegas_atuel.transportista,
  bodegas_atuel.transportista_localidad,
  bodegas_atuel.ingreso,
  bodegas_atuel.ingreso_vino,
  bodegas_atuel.transferencia,
  bodegas_atuel.transferencia_vino
TO bodegas_api;
GRANT UPDATE (fecha) ON bodegas_atuel.comprobante TO bodegas_api;

REVOKE INSERT, UPDATE, DELETE ON
  bodegas_atuel.stock_sala,
  bodegas_atuel.stock_deposito,
  bodegas_atuel.auditoria_precios
FROM bodegas_api;
GRANT SELECT ON
  bodegas_atuel.stock_sala,
  bodegas_atuel.stock_deposito,
  bodegas_atuel.auditoria_precios
TO bodegas_api, bodegas_reportes;

ALTER DEFAULT PRIVILEGES IN SCHEMA bodegas_atuel
  REVOKE ALL ON TABLES FROM PUBLIC;
-- EXECUTE se concede globalmente por defecto: REVOKE por esquema no lo quita.
ALTER DEFAULT PRIVILEGES
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
