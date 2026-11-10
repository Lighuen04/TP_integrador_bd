-- Extensión mínima F: baja de un vino sin movimientos. El saldo cero creado
-- automáticamente por trg_vino_stock_deposito no debe hacer imposible la baja.
-- Ejecutar como propietario autorizado, después de 01–07. No otorga DML de stock.
BEGIN;
SET LOCAL ROLE bodegas_propietario;
SET LOCAL search_path = bodegas_atuel, pg_temp;
CREATE OR REPLACE FUNCTION fn_eliminar_vino_sin_movimientos(p_codigo varchar)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas_atuel, pg_temp
AS $$
BEGIN
  PERFORM 1 FROM vino WHERE codigo_vino=p_codigo FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  -- No se borra stock de sala ni movimientos ni auditoría: sus FK bloquean.
  -- DELETE condicional bloquea el saldo; un incremento concurrente no se pierde.
  DELETE FROM stock_deposito
    WHERE codigo_vino=p_codigo AND cantidad_botellas_disponibles=0;
  DELETE FROM composicion_vino_cepa WHERE codigo_vino=p_codigo;
  DELETE FROM vino_maridaje WHERE codigo_vino=p_codigo;
  DELETE FROM vino WHERE codigo_vino=p_codigo;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION fn_eliminar_vino_sin_movimientos(varchar) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_eliminar_vino_sin_movimientos(varchar) TO bodegas_api;
COMMIT;
