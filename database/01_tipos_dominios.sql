-- PostgreSQL 14+
CREATE SCHEMA IF NOT EXISTS bodegas_atuel;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'bodegas_atuel' AND t.typname = 'estado_documento'
  ) THEN
    CREATE TYPE bodegas_atuel.estado_documento AS ENUM
      ('en_confeccion', 'terminado', 'procesado');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'bodegas_atuel' AND t.typname = 'tipo_cliente'
  ) THEN
    CREATE TYPE bodegas_atuel.tipo_cliente AS ENUM
      ('socio', 'distribuidor', 'exportador');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'bodegas_atuel' AND t.typname = 'dominio_cuit'
  ) THEN
    CREATE DOMAIN bodegas_atuel.dominio_cuit AS varchar(11)
      CHECK (VALUE ~ '^[0-9]{11}$');
  END IF;
END;
$$;
