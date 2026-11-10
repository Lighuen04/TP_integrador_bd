SET search_path TO bodegas_atuel, public;

CREATE OR REPLACE FUNCTION tg_inicializar_descuento_cliente()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas_atuel, pg_temp
AS $$
DECLARE
  v_permisos bigint;
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.descuento := fn_descuento_tipo(NEW.tipo_cliente);
  ELSIF NEW.tipo_cliente IS DISTINCT FROM OLD.tipo_cliente THEN
    NEW.descuento := fn_descuento_tipo(NEW.tipo_cliente);
  ELSIF NEW.descuento IS DISTINCT FROM OLD.descuento
        AND NEW.descuento <> fn_descuento_tipo(NEW.tipo_cliente) THEN
    IF NEW.tipo_cliente = 'exportador'
       AND NEW.descuento = 35 THEN
      SELECT COUNT(*) INTO v_permisos
      FROM permiso_exportacion
      WHERE id_exportador = NEW.id_cliente;
      IF v_permisos > 3 THEN
        RETURN NEW;
      END IF;
    END IF;
    RAISE EXCEPTION
      'El descuento vigente debe corresponder al tipo de cliente; 35 %% solo aplica a exportadores elegibles por U6.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION tg_proteger_comprobante()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas_atuel, pg_temp
AS $$
DECLARE
  v_descuento numeric(5,2);
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF EXISTS (SELECT 1 FROM comprobante_vino
               WHERE numero_comprobante = OLD.numero_comprobante) THEN
      -- D1: bloquear el cliente también serializa cambios de su subtipo.
      PERFORM 1 FROM cliente c JOIN socio s USING (id_cliente)
      WHERE c.id_cliente = OLD.id_cliente AND c.tipo_cliente = 'socio'
      FOR SHARE OF c;
      IF NOT FOUND OR OLD.fecha >= CURRENT_DATE - INTERVAL '5 years' THEN
        RAISE EXCEPTION 'Solo D1 permite eliminar un comprobante con renglones.'
          USING ERRCODE = 'foreign_key_violation';
      END IF;
    END IF;
    -- La FK elimina los detalles después de esta cabecera, sin anular la venta.
    RETURN OLD;
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_descuento := fn_descuento_cliente(NEW.id_cliente);
    NEW.descuento_aplicado := v_descuento;
    NEW.total := 0;
    RETURN NEW;
  END IF;

  IF NEW.id_cliente IS DISTINCT FROM OLD.id_cliente
     OR NEW.id_sala IS DISTINCT FROM OLD.id_sala
     OR NEW.descuento_aplicado IS DISTINCT FROM OLD.descuento_aplicado THEN
    RAISE EXCEPTION
      'El cliente, la sala y el descuento histórico de un comprobante son inmutables.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- RN-08: se acepta únicamente el resultado del cálculo histórico, también
  -- cuando escribe el propietario. El recálculo de los renglones usa esta ruta.
  IF NEW.total IS DISTINCT FROM fn_total_comprobante(OLD.numero_comprobante) THEN
    RAISE EXCEPTION 'El total debe coincidir con sus renglones y descuento histórico.'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION tg_vino_crear_stock_deposito()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas_atuel, pg_temp
AS $$
BEGIN
  INSERT INTO stock_deposito (codigo_vino, cantidad_botellas_disponibles)
  VALUES (NEW.codigo_vino, 0);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION tg_bloquear_composicion_vino()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = bodegas_atuel, pg_temp
AS $$
DECLARE
  v_codigo varchar(40);
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.codigo_vino IS DISTINCT FROM OLD.codigo_vino THEN
      FOR v_codigo IN
        SELECT codigo_vino
        FROM (VALUES (OLD.codigo_vino), (NEW.codigo_vino)) AS codigos(codigo_vino)
        ORDER BY codigo_vino
      LOOP
        PERFORM 1 FROM vino WHERE codigo_vino = v_codigo FOR UPDATE;
      END LOOP;
    ELSE
      PERFORM 1 FROM vino WHERE codigo_vino = NEW.codigo_vino FOR UPDATE;
    END IF;
  ELSE
    v_codigo := CASE WHEN TG_OP = 'DELETE' THEN OLD.codigo_vino ELSE NEW.codigo_vino END;
    PERFORM 1 FROM vino WHERE codigo_vino = v_codigo FOR UPDATE;
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION tg_guardar_tipo_subtipo_cliente()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = bodegas_atuel, pg_temp
AS $$
DECLARE
  v_id integer;
  v_tipo tipo_cliente;
  v_esperado tipo_cliente;
BEGIN
  v_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id_cliente ELSE NEW.id_cliente END;

  IF TG_OP = 'UPDATE' AND NEW.id_cliente IS DISTINCT FROM OLD.id_cliente THEN
    RAISE EXCEPTION 'La clave compartida de un subtipo no se puede modificar.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT tipo_cliente INTO v_tipo
  FROM cliente
  WHERE id_cliente = v_id
  FOR UPDATE;

  IF NOT FOUND THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'No existe el cliente % para el subtipo %', v_id, TG_TABLE_NAME
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  v_esperado := CASE TG_TABLE_NAME
    WHEN 'socio' THEN 'socio'::tipo_cliente
    WHEN 'distribuidor' THEN 'distribuidor'::tipo_cliente
    WHEN 'exportador' THEN 'exportador'::tipo_cliente
  END;

  IF TG_OP <> 'DELETE' AND v_tipo <> v_esperado THEN
    RAISE EXCEPTION 'El cliente % tiene tipo %, no %', v_id, v_tipo, v_esperado
      USING ERRCODE = 'check_violation';
  END IF;

  IF TG_OP = 'INSERT' AND (
       (TG_TABLE_NAME <> 'socio' AND EXISTS (SELECT 1 FROM socio WHERE id_cliente = v_id))
       OR (TG_TABLE_NAME <> 'distribuidor' AND EXISTS (SELECT 1 FROM distribuidor WHERE id_cliente = v_id))
       OR (TG_TABLE_NAME <> 'exportador' AND EXISTS (SELECT 1 FROM exportador WHERE id_cliente = v_id))
     ) THEN
    RAISE EXCEPTION 'El cliente % ya pertenece a otro subtipo', v_id
      USING ERRCODE = 'check_violation';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION tg_proteger_estado_documento()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = bodegas_atuel, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- D5: purga documental, sin volver a aplicar ni revertir existencias.
    IF TG_TABLE_NAME = 'ingreso' THEN
      IF OLD.estado = 'procesado' AND OLD.fecha < CURRENT_DATE - 365 THEN
        RETURN OLD;
      END IF;
    END IF;
    IF OLD.estado <> 'en_confeccion' THEN
      RAISE EXCEPTION
        'Solo se pueden eliminar documentos que estén en confección.'
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.estado <> 'en_confeccion' THEN
      RAISE EXCEPTION 'Los documentos deben crearse en estado en_confeccion.'
        USING ERRCODE = 'check_violation';
    END IF;
    IF TG_TABLE_NAME = 'transferencia' THEN
      NEW.fecha_confeccion := CURRENT_DATE;
    END IF;
    RETURN NEW;
  END IF;

  IF TG_TABLE_NAME = 'transferencia' THEN
    IF NEW.fecha_confeccion IS DISTINCT FROM OLD.fecha_confeccion THEN
      RAISE EXCEPTION 'La fecha de confección de una transferencia es inmutable.'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  -- RN-10/RN-11: el documento ya impactó stock. Ningún atributo de su
  -- cabecera puede cambiar el significado histórico de ese movimiento.
  IF OLD.estado = 'procesado' AND NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'La cabecera de un documento procesado es inmutable.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.estado IS DISTINCT FROM OLD.estado
     AND NOT (
       (OLD.estado = 'en_confeccion' AND NEW.estado = 'terminado')
       OR (OLD.estado = 'terminado' AND NEW.estado = 'procesado')
     ) THEN
    RAISE EXCEPTION 'Transición de estado inválida: % -> %', OLD.estado, NEW.estado
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION tg_validar_lineas_documento()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = bodegas_atuel, pg_temp
AS $$
DECLARE
  v_codigo varchar(40);
  v_estado estado_documento;
BEGIN
  IF TG_TABLE_NAME = 'ingreso_vino' THEN
    IF TG_OP = 'DELETE' THEN
      v_codigo := OLD.codigo_ingreso;
    ELSE
      v_codigo := NEW.codigo_ingreso;
    END IF;
    IF TG_OP = 'UPDATE'
       AND NEW.codigo_ingreso IS DISTINCT FROM OLD.codigo_ingreso THEN
      RAISE EXCEPTION 'No se puede trasladar un renglón entre documentos.'
        USING ERRCODE = 'check_violation';
    END IF;
    SELECT estado INTO v_estado FROM ingreso
    WHERE codigo_ingreso = v_codigo FOR UPDATE;
  ELSE
    IF TG_OP = 'DELETE' THEN
      v_codigo := OLD.numero_solicitud;
    ELSE
      v_codigo := NEW.numero_solicitud;
    END IF;
    IF TG_OP = 'UPDATE'
       AND NEW.numero_solicitud IS DISTINCT FROM OLD.numero_solicitud THEN
      RAISE EXCEPTION 'No se puede trasladar un renglón entre documentos.'
        USING ERRCODE = 'check_violation';
    END IF;
    SELECT estado INTO v_estado FROM transferencia
    WHERE numero_solicitud = v_codigo FOR UPDATE;
  END IF;

  IF NOT FOUND THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RAISE EXCEPTION 'No existe el documento asociado al renglón %', v_codigo
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF v_estado <> 'en_confeccion' THEN
    RAISE EXCEPTION 'No se pueden modificar renglones de un documento que no está en confección.'
      USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION tg_actualizar_total_comprobante()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas_atuel, pg_temp
AS $$
DECLARE
  v_numero_viejo varchar(40);
  v_numero_nuevo varchar(40);
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    v_numero_viejo := OLD.numero_comprobante;
  END IF;
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    v_numero_nuevo := NEW.numero_comprobante;
  END IF;

  IF v_numero_viejo IS NOT NULL AND v_numero_nuevo IS NOT NULL
     AND v_numero_viejo <> v_numero_nuevo THEN
    IF v_numero_viejo < v_numero_nuevo THEN
      PERFORM fn_recalcular_total_comprobante(v_numero_viejo);
      PERFORM fn_recalcular_total_comprobante(v_numero_nuevo);
    ELSE
      PERFORM fn_recalcular_total_comprobante(v_numero_nuevo);
      PERFORM fn_recalcular_total_comprobante(v_numero_viejo);
    END IF;
  ELSE
    PERFORM fn_recalcular_total_comprobante(
      COALESCE(v_numero_nuevo, v_numero_viejo)
    );
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION tg_movimiento_stock_venta()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas_atuel, pg_temp
AS $$
DECLARE
  v_numero varchar(40);
  v_id_sala integer;
  v_fila integer;
BEGIN
  IF TG_OP = 'UPDATE'
     AND NEW.numero_comprobante IS DISTINCT FROM OLD.numero_comprobante THEN
    FOR v_numero IN
      SELECT numero_comprobante
      FROM (VALUES (OLD.numero_comprobante), (NEW.numero_comprobante))
        AS comprobantes(numero_comprobante)
      ORDER BY numero_comprobante
    LOOP
      PERFORM 1
      FROM comprobante
      WHERE numero_comprobante = v_numero
      FOR UPDATE;
    END LOOP;
  ELSIF TG_OP = 'DELETE' THEN
    PERFORM 1
    FROM comprobante
    WHERE numero_comprobante = OLD.numero_comprobante
    FOR UPDATE;
  ELSE
    PERFORM 1
    FROM comprobante
    WHERE numero_comprobante = NEW.numero_comprobante
    FOR UPDATE;
  END IF;

  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    SELECT id_sala INTO v_id_sala
    FROM comprobante
    WHERE numero_comprobante = OLD.numero_comprobante;

    IF NOT FOUND THEN
      -- Cabecera ya eliminada por D1 y FK CASCADE: no hay reversión de venta.
      -- Un DELETE directo de detalle siempre encuentra su cabecera por la FK.
      IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
      RAISE EXCEPTION 'No se encuentra la sala de la venta histórica %',
        OLD.numero_comprobante USING ERRCODE = 'foreign_key_violation';
    END IF;

    INSERT INTO stock_sala (id_sala, codigo_vino, cantidad_stock)
    VALUES (v_id_sala, OLD.codigo_vino, OLD.cantidad)
    ON CONFLICT (id_sala, codigo_vino)
    DO UPDATE SET cantidad_stock = stock_sala.cantidad_stock + EXCLUDED.cantidad_stock;
  END IF;

  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    SELECT id_sala INTO v_id_sala
    FROM comprobante
    WHERE numero_comprobante = NEW.numero_comprobante;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'No existe el comprobante %', NEW.numero_comprobante
        USING ERRCODE = 'foreign_key_violation';
    END IF;

    UPDATE stock_sala
    SET cantidad_stock = cantidad_stock - NEW.cantidad
    WHERE id_sala = v_id_sala
      AND codigo_vino = NEW.codigo_vino
      AND cantidad_stock >= NEW.cantidad;
    GET DIAGNOSTICS v_fila = ROW_COUNT;
    IF v_fila <> 1 THEN
      RAISE EXCEPTION
        'Stock insuficiente para el vino % en la sala %',
        NEW.codigo_vino, v_id_sala
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION tg_auditar_cambio_precio()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas_atuel, pg_temp
AS $$
BEGIN
  IF NEW.precio IS DISTINCT FROM OLD.precio THEN
    INSERT INTO auditoria_precios (
      codigo_vino, precio_anterior, precio_nuevo,
      fecha_del_cambio, hora_del_cambio, usuario_modificacion
    )
    VALUES (
      NEW.codigo_vino, OLD.precio, NEW.precio,
      CURRENT_DATE, LOCALTIME, session_user
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION tg_aplicar_ingreso()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas_atuel, pg_temp
AS $$
DECLARE
  v_linea record;
BEGIN
  IF OLD.estado = 'terminado' AND NEW.estado = 'procesado' THEN
    FOR v_linea IN
      SELECT codigo_vino, cantidad_botellas
      FROM ingreso_vino
      WHERE codigo_ingreso = NEW.codigo_ingreso
      ORDER BY codigo_vino
    LOOP
      INSERT INTO stock_deposito (codigo_vino, cantidad_botellas_disponibles)
      VALUES (v_linea.codigo_vino, v_linea.cantidad_botellas)
      ON CONFLICT (codigo_vino)
      DO UPDATE SET cantidad_botellas_disponibles =
        stock_deposito.cantidad_botellas_disponibles + EXCLUDED.cantidad_botellas_disponibles;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION tg_aplicar_transferencia()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas_atuel, pg_temp
AS $$
DECLARE
  v_linea record;
  v_fila integer;
BEGIN
  IF OLD.estado = 'terminado' AND NEW.estado = 'procesado' THEN
    FOR v_linea IN
      SELECT codigo_vino, cantidad_botellas
      FROM transferencia_vino
      WHERE numero_solicitud = NEW.numero_solicitud
      ORDER BY codigo_vino
    LOOP
      UPDATE stock_deposito
      SET cantidad_botellas_disponibles =
        cantidad_botellas_disponibles - v_linea.cantidad_botellas
      WHERE codigo_vino = v_linea.codigo_vino
        AND cantidad_botellas_disponibles >= v_linea.cantidad_botellas;
      GET DIAGNOSTICS v_fila = ROW_COUNT;
      IF v_fila <> 1 THEN
        RAISE EXCEPTION
          'Stock insuficiente en depósito para el vino %',
          v_linea.codigo_vino
          USING ERRCODE = 'check_violation';
      END IF;

      INSERT INTO stock_sala (id_sala, codigo_vino, cantidad_stock)
      VALUES (NEW.id_sala, v_linea.codigo_vino, v_linea.cantidad_botellas)
      ON CONFLICT (id_sala, codigo_vino)
      DO UPDATE SET cantidad_stock =
        stock_sala.cantidad_stock + EXCLUDED.cantidad_stock;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION tg_validar_composicion_diferida()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas_atuel, pg_temp
AS $$
BEGIN
  IF TG_TABLE_NAME = 'vino' THEN
    PERFORM fn_validar_composicion_vino(NEW.codigo_vino);
  ELSIF TG_OP = 'DELETE' THEN
    PERFORM fn_validar_composicion_vino(OLD.codigo_vino);
  ELSIF TG_OP = 'UPDATE'
        AND NEW.codigo_vino IS DISTINCT FROM OLD.codigo_vino THEN
    PERFORM fn_validar_composicion_vino(OLD.codigo_vino);
    PERFORM fn_validar_composicion_vino(NEW.codigo_vino);
  ELSE
    PERFORM fn_validar_composicion_vino(NEW.codigo_vino);
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION tg_comprobar_cliente_isa_diferido()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas_atuel, pg_temp
AS $$
DECLARE
  v_id integer;
BEGIN
  v_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id_cliente ELSE NEW.id_cliente END;
  PERFORM fn_validar_cliente_isa(v_id);
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_cliente_descuento_base ON cliente;
CREATE TRIGGER trg_cliente_descuento_base
BEFORE INSERT OR UPDATE OF tipo_cliente, descuento ON cliente
FOR EACH ROW EXECUTE FUNCTION tg_inicializar_descuento_cliente();

DROP TRIGGER IF EXISTS trg_comprobante_protegido ON comprobante;
CREATE TRIGGER trg_comprobante_protegido
BEFORE INSERT OR UPDATE OR DELETE ON comprobante
FOR EACH ROW EXECUTE FUNCTION tg_proteger_comprobante();

DROP TRIGGER IF EXISTS trg_vino_stock_deposito ON vino;
CREATE TRIGGER trg_vino_stock_deposito
AFTER INSERT ON vino
FOR EACH ROW EXECUTE FUNCTION tg_vino_crear_stock_deposito();

DROP TRIGGER IF EXISTS trg_composicion_bloqueo ON composicion_vino_cepa;
CREATE TRIGGER trg_composicion_bloqueo
BEFORE INSERT OR UPDATE OR DELETE ON composicion_vino_cepa
FOR EACH ROW EXECUTE FUNCTION tg_bloquear_composicion_vino();

DROP TRIGGER IF EXISTS trg_composicion_validacion ON composicion_vino_cepa;
CREATE CONSTRAINT TRIGGER trg_composicion_validacion
AFTER INSERT OR UPDATE OR DELETE ON composicion_vino_cepa
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION tg_validar_composicion_diferida();

DROP TRIGGER IF EXISTS trg_vino_composicion_obligatoria ON vino;
CREATE CONSTRAINT TRIGGER trg_vino_composicion_obligatoria
AFTER INSERT OR UPDATE ON vino
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION tg_validar_composicion_diferida();

DROP TRIGGER IF EXISTS trg_cliente_isa_lock ON socio;
CREATE TRIGGER trg_cliente_isa_lock
BEFORE INSERT OR UPDATE OR DELETE ON socio
FOR EACH ROW EXECUTE FUNCTION tg_guardar_tipo_subtipo_cliente();
DROP TRIGGER IF EXISTS trg_distribuidor_isa_lock ON distribuidor;
CREATE TRIGGER trg_distribuidor_isa_lock
BEFORE INSERT OR UPDATE OR DELETE ON distribuidor
FOR EACH ROW EXECUTE FUNCTION tg_guardar_tipo_subtipo_cliente();
DROP TRIGGER IF EXISTS trg_exportador_isa_lock ON exportador;
CREATE TRIGGER trg_exportador_isa_lock
BEFORE INSERT OR UPDATE OR DELETE ON exportador
FOR EACH ROW EXECUTE FUNCTION tg_guardar_tipo_subtipo_cliente();

DROP TRIGGER IF EXISTS trg_cliente_isa_diferido ON cliente;
CREATE CONSTRAINT TRIGGER trg_cliente_isa_diferido
AFTER INSERT OR UPDATE OR DELETE ON cliente
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION tg_comprobar_cliente_isa_diferido();
DROP TRIGGER IF EXISTS trg_socio_isa_diferido ON socio;
CREATE CONSTRAINT TRIGGER trg_socio_isa_diferido
AFTER INSERT OR UPDATE OR DELETE ON socio
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION tg_comprobar_cliente_isa_diferido();
DROP TRIGGER IF EXISTS trg_distribuidor_isa_diferido ON distribuidor;
CREATE CONSTRAINT TRIGGER trg_distribuidor_isa_diferido
AFTER INSERT OR UPDATE OR DELETE ON distribuidor
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION tg_comprobar_cliente_isa_diferido();
DROP TRIGGER IF EXISTS trg_exportador_isa_diferido ON exportador;
CREATE CONSTRAINT TRIGGER trg_exportador_isa_diferido
AFTER INSERT OR UPDATE OR DELETE ON exportador
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION tg_comprobar_cliente_isa_diferido();

DROP TRIGGER IF EXISTS trg_ingreso_estado ON ingreso;
CREATE TRIGGER trg_ingreso_estado
BEFORE INSERT OR UPDATE OR DELETE ON ingreso
FOR EACH ROW EXECUTE FUNCTION tg_proteger_estado_documento();
DROP TRIGGER IF EXISTS trg_transferencia_estado ON transferencia;
CREATE TRIGGER trg_transferencia_estado
BEFORE INSERT OR UPDATE OR DELETE ON transferencia
FOR EACH ROW EXECUTE FUNCTION tg_proteger_estado_documento();

DROP TRIGGER IF EXISTS trg_ingreso_lineas_estado ON ingreso_vino;
CREATE TRIGGER trg_ingreso_lineas_estado
BEFORE INSERT OR UPDATE OR DELETE ON ingreso_vino
FOR EACH ROW EXECUTE FUNCTION tg_validar_lineas_documento();
DROP TRIGGER IF EXISTS trg_transferencia_lineas_estado ON transferencia_vino;
CREATE TRIGGER trg_transferencia_lineas_estado
BEFORE INSERT OR UPDATE OR DELETE ON transferencia_vino
FOR EACH ROW EXECUTE FUNCTION tg_validar_lineas_documento();

DROP TRIGGER IF EXISTS trg_comprobante_vino_stock ON comprobante_vino;
CREATE TRIGGER trg_comprobante_vino_stock
BEFORE INSERT OR UPDATE OR DELETE ON comprobante_vino
FOR EACH ROW EXECUTE FUNCTION tg_movimiento_stock_venta();
DROP TRIGGER IF EXISTS trg_comprobante_vino_total ON comprobante_vino;
CREATE TRIGGER trg_comprobante_vino_total
AFTER INSERT OR UPDATE OR DELETE ON comprobante_vino
FOR EACH ROW EXECUTE FUNCTION tg_actualizar_total_comprobante();

DROP TRIGGER IF EXISTS trg_comprobante_devolver_stock ON comprobante;
DROP FUNCTION IF EXISTS tg_reintegrar_stock_al_borrar_comprobante();
DROP TRIGGER IF EXISTS trg_comprobante_eliminar_detalles ON comprobante;

DROP TRIGGER IF EXISTS trg_vino_auditar_precio ON vino;
CREATE TRIGGER trg_vino_auditar_precio
AFTER UPDATE OF precio ON vino
FOR EACH ROW EXECUTE FUNCTION tg_auditar_cambio_precio();

DROP TRIGGER IF EXISTS trg_ingreso_aplicar_stock ON ingreso;
CREATE TRIGGER trg_ingreso_aplicar_stock
AFTER UPDATE OF estado ON ingreso
FOR EACH ROW EXECUTE FUNCTION tg_aplicar_ingreso();
DROP TRIGGER IF EXISTS trg_transferencia_aplicar_stock ON transferencia;
CREATE TRIGGER trg_transferencia_aplicar_stock
AFTER UPDATE OF estado ON transferencia
FOR EACH ROW EXECUTE FUNCTION tg_aplicar_transferencia();

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA bodegas_atuel FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_descuento_cliente(integer),
  fn_antiguedad_anios(date),
  fn_stock_sala(integer, varchar),
  fn_total_comprobante(varchar),
  fn_recalcular_totales_comprobantes()
TO bodegas_api;
GRANT EXECUTE ON PROCEDURE sp_procesar_ingreso(varchar),
  sp_procesar_transferencia(varchar)
TO bodegas_api;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA bodegas_atuel TO bodegas_propietario;
GRANT EXECUTE ON PROCEDURE sp_procesar_ingreso(varchar),
  sp_procesar_transferencia(varchar)
TO bodegas_propietario;
