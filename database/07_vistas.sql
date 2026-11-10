SET search_path TO bodegas_atuel, public;

CREATE OR REPLACE VIEW vw_stock_total_vino AS
SELECT
  v.codigo_vino,
  v.nombre_comercial,
  COALESCE(sd.cantidad_botellas_disponibles, 0)::bigint
    + COALESCE(ss.cantidad_salas, 0)::bigint AS cantidad_total_disponible
FROM vino AS v
LEFT JOIN stock_deposito AS sd
  ON sd.codigo_vino = v.codigo_vino
LEFT JOIN (
  SELECT codigo_vino, SUM(cantidad_stock)::bigint AS cantidad_salas
  FROM stock_sala
  GROUP BY codigo_vino
) AS ss
  ON ss.codigo_vino = v.codigo_vino;

CREATE OR REPLACE VIEW vw_ventas_mensuales_sala AS
SELECT
  s.id_sala,
  date_trunc('month', c.fecha)::date AS mes,
  COUNT(*) AS cantidad_comprobantes,
  SUM(c.total)::numeric(14,2) AS total_ventas
FROM sala_venta AS s
JOIN comprobante AS c ON c.id_sala = s.id_sala
GROUP BY s.id_sala, date_trunc('month', c.fecha)::date;

CREATE OR REPLACE VIEW vw_documentos_pendientes AS
SELECT
  'ingreso'::varchar(16) AS tipo_documento,
  i.codigo_ingreso AS identificador,
  i.fecha AS fecha_documento,
  i.estado::text AS estado
FROM ingreso AS i
WHERE i.estado <> 'procesado'
UNION ALL
SELECT
  'transferencia'::varchar(16) AS tipo_documento,
  t.numero_solicitud AS identificador,
  t.fecha_confeccion AS fecha_documento,
  t.estado::text AS estado
FROM transferencia AS t
WHERE t.estado <> 'procesado';

GRANT SELECT ON
  vw_stock_total_vino,
  vw_ventas_mensuales_sala,
  vw_documentos_pendientes
TO bodegas_api, bodegas_reportes, bodegas_propietario;

-- Cierre de instalación: GRANT no transfiere propiedad. Solo se recorren los
-- objetos de este esquema; las secuencias identity siguen al dueño de su tabla.
DO $$
DECLARE
  v_objeto record;
BEGIN
  ALTER SCHEMA bodegas_atuel OWNER TO bodegas_propietario;
  FOR v_objeto IN
    SELECT c.relname, c.relkind
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'bodegas_atuel' AND c.relkind IN ('r', 'v')
  LOOP
    EXECUTE format('ALTER %s bodegas_atuel.%I OWNER TO bodegas_propietario',
      CASE v_objeto.relkind WHEN 'v' THEN 'VIEW' ELSE 'TABLE' END,
      v_objeto.relname);
  END LOOP;
  FOR v_objeto IN
    SELECT p.oid::regprocedure AS firma
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'bodegas_atuel'
  LOOP
    EXECUTE format('ALTER ROUTINE %s OWNER TO bodegas_propietario', v_objeto.firma);
  END LOOP;
  ALTER TYPE estado_documento OWNER TO bodegas_propietario;
  ALTER TYPE tipo_cliente OWNER TO bodegas_propietario;
  ALTER DOMAIN dominio_cuit OWNER TO bodegas_propietario;
END;
$$;

-- Los defaults son por creador: proteger también futuros objetos del dueño.
ALTER DEFAULT PRIVILEGES FOR ROLE bodegas_propietario IN SCHEMA bodegas_atuel
  REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE bodegas_propietario
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
