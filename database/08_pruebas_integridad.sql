-- Ejecutar después de 01-07 en una base de pruebas vacía.
-- Todo el fixture se revierte al final.
\set ON_ERROR_STOP on
BEGIN;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO bodegas_atuel.localidad
  (codigo_postal, nombre, provincia, encargado_regional)
VALUES ('TST000000000001', 'Localidad prueba', 'Mendoza', 'Responsable prueba');

INSERT INTO bodegas_atuel.sala_venta
  (id_sala, calle, numero, cierre_semanal, codigo_postal)
VALUES (2100000001, 'Calle prueba', '100', 'domingo', 'TST000000000001');

INSERT INTO bodegas_atuel.bodega (cuit, razon_social, domicilio)
VALUES ('20123456789', 'Bodega de prueba', 'Domicilio de prueba');

INSERT INTO bodegas_atuel.cepa (id_cepa, nombre, tipo)
VALUES (2100000001, 'Cepa de prueba', 'tinta');

INSERT INTO bodegas_atuel.vino
  (codigo_vino, nombre_comercial, tipo, anada, presentacion_ml,
   graduacion_alcoholica, precio, cuit_bodega)
VALUES
  ('TST-WINE-01', 'Vino de prueba', 'tinto', 2025, 750, 13.50, 100.00, '20123456789');

INSERT INTO bodegas_atuel.composicion_vino_cepa
  (codigo_vino, id_cepa, porcentaje_corte)
VALUES ('TST-WINE-01', 2100000001, 100.00);

INSERT INTO bodegas_atuel.stock_sala (id_sala, codigo_vino, cantidad_stock)
VALUES (2100000001, 'TST-WINE-01', 10);

SET CONSTRAINTS ALL IMMEDIATE;

DO $$
DECLARE
  v_tablas integer;
  v_fks integer;
  v_unique integer;
BEGIN
  SELECT COUNT(*) INTO v_tablas
  FROM information_schema.tables
  WHERE table_schema = 'bodegas_atuel' AND table_type = 'BASE TABLE';
  IF v_tablas <> 29 THEN
    RAISE EXCEPTION 'Se esperaban 29 tablas; se encontraron %', v_tablas;
  END IF;

  SELECT COUNT(*) INTO v_fks
  FROM pg_constraint c
  JOIN pg_namespace n ON n.oid = c.connamespace
  WHERE n.nspname = 'bodegas_atuel' AND c.contype = 'f';
  IF v_fks <> 35 THEN
    RAISE EXCEPTION 'Se esperaban 35 FK; se encontraron %', v_fks;
  END IF;
  SELECT COUNT(*) INTO v_unique
  FROM pg_constraint c
  JOIN pg_namespace n ON n.oid = c.connamespace
  WHERE n.nspname = 'bodegas_atuel' AND c.contype = 'u';
  IF v_unique <> 4 THEN
    RAISE EXCEPTION 'Se esperaban 4 UNIQUE adicionales; se encontraron %', v_unique;
  END IF;
  RAISE NOTICE 'OK: estructura física con 29 tablas, 35 FK y 4 UNIQUE adicionales';

  -- H7: verificar propiedad real, incluidas vistas, índices y secuencias.
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'bodegas_atuel'
      AND pg_get_userbyid(c.relowner) <> 'bodegas_propietario'
  ) OR EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'bodegas_atuel'
      AND pg_get_userbyid(p.proowner) <> 'bodegas_propietario'
  ) OR EXISTS (
    SELECT 1 FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'bodegas_atuel'
      AND pg_get_userbyid(t.typowner) <> 'bodegas_propietario'
  ) OR (SELECT pg_get_userbyid(nspowner) FROM pg_namespace
        WHERE nspname = 'bodegas_atuel') IS DISTINCT FROM 'bodegas_propietario' THEN
    RAISE EXCEPTION 'Propiedad incompleta de los objetos del esquema';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'bodegas_atuel' AND p.prosecdef
      AND NOT COALESCE(p.proconfig @> ARRAY['search_path=bodegas_atuel, pg_temp'], false)
  ) THEN
    RAISE EXCEPTION 'SECURITY DEFINER sin search_path controlado';
  END IF;
  IF pg_has_role('bodegas_api', 'bodegas_propietario', 'MEMBER')
     OR pg_has_role('bodegas_reportes', 'bodegas_propietario', 'MEMBER') THEN
    RAISE EXCEPTION 'API/reportes no deben heredar el rol propietario';
  END IF;
  RAISE NOTICE 'OK H7: propiedad de esquema/relaciones/tipos/rutinas y SECURITY DEFINER';
END;
$$;

DO $$
BEGIN
  BEGIN
    INSERT INTO bodegas_atuel.localidad
      (codigo_postal, nombre, provincia, encargado_regional)
    VALUES ('TST000000000001', 'Duplicada', 'Mendoza', 'Otro');
    RAISE EXCEPTION 'Falló prueba: PK duplicada aceptada' USING ERRCODE = 'P0001';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'OK: PK duplicada rechazada';
  END;

  BEGIN
    INSERT INTO bodegas_atuel.sala_venta
      (id_sala, calle, numero, cierre_semanal, codigo_postal)
    VALUES (2100000002, 'Calle', '2', 'domingo', 'NO-EXISTE');
    RAISE EXCEPTION 'Falló prueba: FK inexistente aceptada' USING ERRCODE = 'P0001';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'OK: FK inexistente rechazada';
  END;

  BEGIN
    INSERT INTO bodegas_atuel.bodega (cuit, razon_social, domicilio)
    VALUES ('123', 'CUIT inválido', 'Domicilio');
    RAISE EXCEPTION 'Falló prueba: dominio CUIT inválido aceptado' USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK: dominio CUIT inválido rechazado';
  END;

  BEGIN
    INSERT INTO bodegas_atuel.stock_sala (id_sala, codigo_vino, cantidad_stock)
    VALUES (2100000001, 'TST-WINE-01', -1);
    RAISE EXCEPTION 'Falló prueba: stock negativo aceptado' USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK: CHECK de stock no negativo';
  END;

  BEGIN
    INSERT INTO bodegas_atuel.stock_sala (id_sala, codigo_vino, cantidad_stock)
    VALUES (2100000001, 'TST-WINE-01', 1);
    RAISE EXCEPTION 'Falló prueba: PK compuesta duplicada aceptada' USING ERRCODE = 'P0001';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'OK: PK compuesta duplicada rechazada';
  END;

  BEGIN
    UPDATE bodegas_atuel.vino SET precio = 0 WHERE codigo_vino = 'TST-WINE-01';
    RAISE EXCEPTION 'Falló prueba: precio no positivo aceptado' USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK: CHECK de precio positivo';
  END;
END;
$$;

ROLLBACK;
