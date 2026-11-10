SET search_path TO bodegas_atuel, public;

CREATE OR REPLACE FUNCTION fn_descuento_tipo(p_tipo tipo_cliente)
RETURNS numeric(5,2)
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = bodegas_atuel, pg_temp
AS $$
  SELECT CASE p_tipo
    WHEN 'socio'::tipo_cliente THEN 10.00
    WHEN 'distribuidor'::tipo_cliente THEN 20.00
    WHEN 'exportador'::tipo_cliente THEN 30.00
  END::numeric(5,2)
$$;

CREATE OR REPLACE FUNCTION fn_descuento_cliente(p_id_cliente integer)
RETURNS numeric(5,2)
LANGUAGE plpgsql
STABLE
STRICT
SET search_path = bodegas_atuel, pg_temp
AS $$
DECLARE
  v_descuento numeric(5,2);
BEGIN
  SELECT descuento INTO v_descuento
  FROM cliente
  WHERE id_cliente = p_id_cliente;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe el cliente %', p_id_cliente
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  RETURN v_descuento;
END;
$$;

CREATE OR REPLACE FUNCTION fn_antiguedad_anios(p_fecha date)
RETURNS integer
LANGUAGE sql
STABLE
STRICT
AS $$
  SELECT EXTRACT(YEAR FROM age(CURRENT_DATE, p_fecha))::integer
$$;

CREATE OR REPLACE FUNCTION fn_stock_sala(
  p_id_sala integer,
  p_codigo_vino varchar
)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = bodegas_atuel, pg_temp
AS $$
  SELECT COALESCE((
    SELECT cantidad_stock
    FROM stock_sala
    WHERE id_sala = p_id_sala AND codigo_vino = p_codigo_vino
  ), 0)
$$;

CREATE OR REPLACE FUNCTION fn_total_comprobante(p_numero_comprobante varchar)
RETURNS numeric(12,2)
LANGUAGE plpgsql
STABLE
STRICT
SET search_path = bodegas_atuel, pg_temp
AS $$
DECLARE
  v_descuento numeric(5,2);
  v_bruto numeric;
BEGIN
  SELECT c.descuento_aplicado,
         COALESCE(SUM(cv.cantidad::numeric * cv.precio), 0)
    INTO v_descuento, v_bruto
  FROM comprobante AS c
  LEFT JOIN comprobante_vino AS cv
    ON cv.numero_comprobante = c.numero_comprobante
  WHERE c.numero_comprobante = p_numero_comprobante
  GROUP BY c.descuento_aplicado;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe el comprobante %', p_numero_comprobante
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  RETURN ROUND(v_bruto * (1 - v_descuento / 100), 2)::numeric(12,2);
END;
$$;

CREATE OR REPLACE FUNCTION fn_recalcular_total_comprobante(
  p_numero_comprobante varchar
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
VOLATILE
STRICT
SET search_path = bodegas_atuel, pg_temp
AS $$
DECLARE
  v_total numeric(12,2);
BEGIN
  PERFORM 1
  FROM comprobante
  WHERE numero_comprobante = p_numero_comprobante
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  v_total := fn_total_comprobante(p_numero_comprobante);
  UPDATE comprobante
  SET total = v_total
  WHERE numero_comprobante = p_numero_comprobante;
END;
$$;

CREATE OR REPLACE FUNCTION fn_recalcular_totales_comprobantes()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
VOLATILE
SET search_path = bodegas_atuel, pg_temp
AS $$
DECLARE
  v_numero varchar(40);
  v_cantidad bigint := 0;
BEGIN
  FOR v_numero IN
    SELECT numero_comprobante
    FROM comprobante
    ORDER BY numero_comprobante
  LOOP
    PERFORM fn_recalcular_total_comprobante(v_numero);
    v_cantidad := v_cantidad + 1;
  END LOOP;
  RETURN v_cantidad;
END;
$$;

CREATE OR REPLACE FUNCTION fn_validar_composicion_vino(p_codigo_vino varchar)
RETURNS void
LANGUAGE plpgsql
STABLE
STRICT
SET search_path = bodegas_atuel, pg_temp
AS $$
DECLARE
  v_cantidad bigint;
  v_suma numeric;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM vino WHERE codigo_vino = p_codigo_vino) THEN
    RETURN;
  END IF;

  SELECT COUNT(*), COALESCE(SUM(porcentaje_corte), 0)
    INTO v_cantidad, v_suma
  FROM composicion_vino_cepa
  WHERE codigo_vino = p_codigo_vino;

  IF v_cantidad = 0 OR v_suma <> 100 THEN
    RAISE EXCEPTION
      'La composición final del vino % debe contener cepas y sumar 100 %% (actual: %)',
      p_codigo_vino, v_suma
      USING ERRCODE = 'check_violation';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_validar_cliente_isa(p_id_cliente integer)
RETURNS void
LANGUAGE plpgsql
STABLE
STRICT
SET search_path = bodegas_atuel, pg_temp
AS $$
DECLARE
  v_tipo tipo_cliente;
  v_socio boolean;
  v_distribuidor boolean;
  v_exportador boolean;
BEGIN
  SELECT tipo_cliente INTO v_tipo
  FROM cliente
  WHERE id_cliente = p_id_cliente;

  IF NOT FOUND THEN
    IF EXISTS (SELECT 1 FROM socio WHERE id_cliente = p_id_cliente)
       OR EXISTS (SELECT 1 FROM distribuidor WHERE id_cliente = p_id_cliente)
       OR EXISTS (SELECT 1 FROM exportador WHERE id_cliente = p_id_cliente) THEN
      RAISE EXCEPTION 'Subtipo sin supertipo para cliente %', p_id_cliente
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN;
  END IF;

  SELECT EXISTS (SELECT 1 FROM socio WHERE id_cliente = p_id_cliente),
         EXISTS (SELECT 1 FROM distribuidor WHERE id_cliente = p_id_cliente),
         EXISTS (SELECT 1 FROM exportador WHERE id_cliente = p_id_cliente)
    INTO v_socio, v_distribuidor, v_exportador;

  IF ((CASE WHEN v_socio THEN 1 ELSE 0 END)
      + (CASE WHEN v_distribuidor THEN 1 ELSE 0 END)
      + (CASE WHEN v_exportador THEN 1 ELSE 0 END)) <> 1
     OR (v_tipo = 'socio' AND NOT v_socio)
     OR (v_tipo = 'distribuidor' AND NOT v_distribuidor)
     OR (v_tipo = 'exportador' AND NOT v_exportador) THEN
    RAISE EXCEPTION
      'Cliente % debe pertenecer exactamente al subtipo indicado (%).',
      p_id_cliente, v_tipo
      USING ERRCODE = 'check_violation';
  END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_procesar_ingreso(p_codigo_ingreso varchar)
LANGUAGE plpgsql
SET search_path = bodegas_atuel, pg_temp
AS $$
DECLARE
  v_estado estado_documento;
BEGIN
  SELECT estado INTO v_estado
  FROM ingreso
  WHERE codigo_ingreso = p_codigo_ingreso
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe el ingreso %', p_codigo_ingreso
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  IF v_estado <> 'terminado' THEN
    RAISE EXCEPTION 'El ingreso % debe estar terminado; estado actual: %',
      p_codigo_ingreso, v_estado
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  UPDATE ingreso
  SET estado = 'procesado'
  WHERE codigo_ingreso = p_codigo_ingreso;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_procesar_transferencia(p_numero_solicitud varchar)
LANGUAGE plpgsql
SET search_path = bodegas_atuel, pg_temp
AS $$
DECLARE
  v_estado estado_documento;
BEGIN
  SELECT estado INTO v_estado
  FROM transferencia
  WHERE numero_solicitud = p_numero_solicitud
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe la transferencia %', p_numero_solicitud
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  IF v_estado <> 'terminado' THEN
    RAISE EXCEPTION
      'La transferencia % debe estar terminada; estado actual: %',
      p_numero_solicitud, v_estado
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  UPDATE transferencia
  SET estado = 'procesado'
  WHERE numero_solicitud = p_numero_solicitud;
END;
$$;
