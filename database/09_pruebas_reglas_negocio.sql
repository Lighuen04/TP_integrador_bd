-- Pruebas de RN-01 a RN-15 sobre una base de pruebas vacía ya migrada.
-- El fixture usa claves reservadas para pruebas y se revierte al final.
\set ON_ERROR_STOP on
BEGIN;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO bodegas_atuel.localidad
  (codigo_postal, nombre, provincia, encargado_regional)
VALUES ('TST000000000002', 'Localidad RN', 'Mendoza', 'Encargado RN');
INSERT INTO bodegas_atuel.sala_venta
  (id_sala, calle, numero, cierre_semanal, codigo_postal)
VALUES (2100000011, 'Calle RN', '11', 'domingo', 'TST000000000002');
INSERT INTO bodegas_atuel.bodega (cuit, razon_social, domicilio)
VALUES ('20234567891', 'Bodega RN', 'Domicilio RN');
INSERT INTO bodegas_atuel.transportista
  (codigo_transporte, razon_social, cuit, email, telefono, domicilio)
VALUES ('TST-TRANS-01', 'Transporte RN', '20345678912', 'rn@example.invalid', '2600000000', 'Domicilio RN');
INSERT INTO bodegas_atuel.cepa (id_cepa, nombre, tipo)
VALUES (2100000011, 'Cepa RN', 'tinta');
INSERT INTO bodegas_atuel.finca
  (id_finca, nombre, superficie_total, departamento, codigo_postal)
VALUES (2100000011, 'Finca RN', 20.000, 'San Rafael', 'TST000000000002');
INSERT INTO bodegas_atuel.parcela
  (id_finca, numero_parcela, superficie_total, anio_plantacion, id_cepa)
VALUES (2100000011, 1, 5.000, 2010, 2100000011);

INSERT INTO bodegas_atuel.vino
  (codigo_vino, nombre_comercial, tipo, anada, presentacion_ml,
   graduacion_alcoholica, precio, cuit_bodega)
VALUES ('TST-WINE-RN', 'Vino RN', 'tinto', 2024, 750, 14.00, 100.00, '20234567891');
INSERT INTO bodegas_atuel.composicion_vino_cepa
  (codigo_vino, id_cepa, porcentaje_corte)
VALUES ('TST-WINE-RN', 2100000011, 100.00);

INSERT INTO bodegas_atuel.cliente
  (id_cliente, nombre, tipo_cliente, tipo_documento, numero_documento, direccion,
   codigo_postal, descuento)
VALUES
  (2100000011, 'Socio RN', 'socio', 'DNI', 'TST-SOCIO', 'Domicilio 1', 'TST000000000002', 0),
  (2100000012, 'Exportadora RN', 'exportador', 'DNI', 'TST-EXPORTADOR', 'Domicilio 2', 'TST000000000002', 0);
INSERT INTO bodegas_atuel.socio (id_cliente) VALUES (2100000011);
INSERT INTO bodegas_atuel.exportador (id_cliente, pais_destino)
VALUES (2100000012, 'Chile');
INSERT INTO bodegas_atuel.permiso_exportacion
  (codigo_permiso, id_exportador, fecha_emision, fecha_vencimiento)
VALUES
  ('TST-PERM-01', 2100000012, CURRENT_DATE, CURRENT_DATE + 1),
  ('TST-PERM-02', 2100000012, CURRENT_DATE, CURRENT_DATE + 2),
  ('TST-PERM-03', 2100000012, CURRENT_DATE, CURRENT_DATE + 3),
  ('TST-PERM-04', 2100000012, CURRENT_DATE, CURRENT_DATE + 4);

INSERT INTO bodegas_atuel.lote_uva
  (numero_lote, id_finca, numero_parcela, campania, fecha_cosecha,
   kilos_cosechados, cuit_bodega_destino)
VALUES (2100000011, 2100000011, 1, 2025, CURRENT_DATE, 100.000, '20234567891');
INSERT INTO bodegas_atuel.stock_sala (id_sala, codigo_vino, cantidad_stock)
VALUES (2100000011, 'TST-WINE-RN', 10);
INSERT INTO bodegas_atuel.comprobante
  (numero_comprobante, fecha, id_cliente, id_sala, descuento_aplicado, total)
VALUES ('TST-COMP-RN', CURRENT_DATE, 2100000012, 2100000011, 0, 999);

SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

DO $$
DECLARE
  v_valor numeric;
  v_stock integer;
  v_total numeric(12,2);
  v_auditorias bigint;
  v_usuario varchar(160);
BEGIN
  -- RN-01 y RN-15: precio > 0 y graduación alcohólica entre 5 y 20.
  BEGIN
    UPDATE bodegas_atuel.vino SET graduacion_alcoholica = 21
    WHERE codigo_vino = 'TST-WINE-RN';
    RAISE EXCEPTION 'Graduación fuera de rango aceptada' USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK RN-01/RN-15: límites de precio/graduación protegidos';
  END;

  -- RN-02/RN-03: FK y ubicación única por fila; varias salas pueden referenciar la misma Localidad.
  INSERT INTO bodegas_atuel.sala_venta
    (id_sala, calle, numero, cierre_semanal, codigo_postal)
  VALUES (2100000012, 'Otra calle', '12', 'lunes', 'TST000000000002');
  BEGIN
    INSERT INTO bodegas_atuel.empleado
      (cuit, nombre, fecha_laboral, salario, id_sala)
    VALUES ('20456789123', 'Empleado RN', CURRENT_DATE, 1000, 999999999);
    RAISE EXCEPTION 'Empleado con sala inexistente aceptado' USING ERRCODE = 'P0001';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'OK RN-02/RN-03: referencia de sala/localidad validada';
  END;

  -- RN-04: no más de una cosecha por parcela y campaña.
  BEGIN
    INSERT INTO bodegas_atuel.lote_uva
      (numero_lote, id_finca, numero_parcela, campania, fecha_cosecha,
       kilos_cosechados, cuit_bodega_destino)
    VALUES (2100000012, 2100000011, 1, 2025, CURRENT_DATE, 50, '20234567891');
    RAISE EXCEPTION 'Cosecha duplicada aceptada' USING ERRCODE = 'P0001';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'OK RN-04: UNIQUE parcela/campaña';
  END;

  BEGIN
    INSERT INTO bodegas_atuel.vino
      (codigo_vino, nombre_comercial, tipo, anada, presentacion_ml,
       graduacion_alcoholica, precio, cuit_bodega)
    VALUES ('TST-WINE-DUP', 'Vino RN', 'rosado', 2024, 750, 12, 100, '20234567891');
    RAISE EXCEPTION 'UNIQUE de nombre/añada/presentación omitido' USING ERRCODE = 'P0001';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'OK: UNIQUE de nombre/añada/presentación de vino';
  END;

  BEGIN
    INSERT INTO bodegas_atuel.cliente
      (id_cliente, nombre, tipo_cliente, tipo_documento, numero_documento, direccion,
       codigo_postal, descuento)
    VALUES
      (2100000099, 'Duplicado RN', 'socio', 'DNI', 'TST-SOCIO', 'Domicilio duplicado',
       'TST000000000002', 0);
    RAISE EXCEPTION 'UNIQUE de documento de cliente omitido' USING ERRCODE = 'P0001';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'OK: UNIQUE de tipo y número de documento de cliente';
  END;

  BEGIN
    INSERT INTO bodegas_atuel.transportista
      (codigo_transporte, razon_social, cuit, email, telefono, domicilio)
    VALUES
      ('TST-TRANS-DUP', 'Transporte duplicado', '20345678912',
       'duplicado@example.invalid', '2600000001', 'Otro domicilio');
    RAISE EXCEPTION 'UNIQUE de CUIT de transportista omitido' USING ERRCODE = 'P0001';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'OK: UNIQUE de CUIT de transportista';
  END;

  -- RN-05: validar suma 100 al final de la transacción, no por cada sentencia intermedia.
  BEGIN
    INSERT INTO bodegas_atuel.vino
      (codigo_vino, nombre_comercial, tipo, anada, presentacion_ml,
       graduacion_alcoholica, precio, cuit_bodega)
    VALUES ('TST-WINE-BAD', 'Vino composición inválida', 'tinto', 2024, 750, 12, 100, '20234567891');
    INSERT INTO bodegas_atuel.composicion_vino_cepa
      (codigo_vino, id_cepa, porcentaje_corte)
    VALUES ('TST-WINE-BAD', 2100000011, 99);
    SET CONSTRAINTS ALL IMMEDIATE;
    RAISE EXCEPTION 'Composición distinta de 100 aceptada' USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK RN-05: composición diferida rechaza suma distinta de 100';
  END;
  SET CONSTRAINTS ALL DEFERRED;

  -- RN-06/U6: tasas iniciales por subtipo y actualización a 35 % para exportadores elegibles.
  SELECT descuento INTO v_valor FROM bodegas_atuel.cliente WHERE id_cliente = 2100000011;
  IF v_valor <> 10 THEN RAISE EXCEPTION 'Descuento base de socio incorrecto: %', v_valor; END IF;
  SELECT descuento INTO v_valor FROM bodegas_atuel.cliente WHERE id_cliente = 2100000012;
  IF v_valor <> 30 THEN RAISE EXCEPTION 'Descuento base de exportador incorrecto: %', v_valor; END IF;
  UPDATE bodegas_atuel.cliente AS c
  SET descuento = 35
  WHERE c.id_cliente = 2100000012
    AND (SELECT COUNT(*) FROM bodegas_atuel.permiso_exportacion p
         WHERE p.id_exportador = c.id_cliente) > 3;
  IF (SELECT descuento FROM bodegas_atuel.cliente WHERE id_cliente = 2100000012) <> 35 THEN
    RAISE EXCEPTION 'U6 no actualizó el descuento elegible';
  END IF;
  RAISE NOTICE 'OK RN-06/U6: descuentos base y tasa elegible';

  -- RN-07: vigencia del permiso.
  BEGIN
    INSERT INTO bodegas_atuel.permiso_exportacion
      (codigo_permiso, id_exportador, fecha_emision, fecha_vencimiento)
    VALUES ('TST-PERM-BAD', 2100000012, CURRENT_DATE, CURRENT_DATE);
    RAISE EXCEPTION 'Permiso con fechas inválidas aceptado' USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK RN-07: fecha de vencimiento posterior';
  END;

  -- RN-08/RN-09: copia histórica, total automático y stock atómico.
  INSERT INTO bodegas_atuel.comprobante_vino
    (numero_comprobante, codigo_vino, cantidad, precio)
  VALUES ('TST-COMP-RN', 'TST-WINE-RN', 2, 100);
  SELECT descuento_aplicado, total INTO v_valor, v_total
  FROM bodegas_atuel.comprobante WHERE numero_comprobante = 'TST-COMP-RN';
  SELECT cantidad_stock INTO v_stock FROM bodegas_atuel.stock_sala
  WHERE id_sala = 2100000011 AND codigo_vino = 'TST-WINE-RN';
  IF v_valor <> 30 OR v_total <> 140 OR v_stock <> 8 THEN
    RAISE EXCEPTION 'Venta/total/stock incorrectos: desc %, total %, stock %',
      v_valor, v_total, v_stock;
  END IF;
  UPDATE bodegas_atuel.comprobante_vino
  SET cantidad = 3, precio = 120
  WHERE numero_comprobante = 'TST-COMP-RN' AND codigo_vino = 'TST-WINE-RN';
  SELECT total INTO v_total FROM bodegas_atuel.comprobante
  WHERE numero_comprobante = 'TST-COMP-RN';
  SELECT cantidad_stock INTO v_stock FROM bodegas_atuel.stock_sala
  WHERE id_sala = 2100000011 AND codigo_vino = 'TST-WINE-RN';
  IF v_total <> 252 OR v_stock <> 7 THEN
    RAISE EXCEPTION 'UPDATE de renglón no mantuvo total/stock: %, %', v_total, v_stock;
  END IF;
  DELETE FROM bodegas_atuel.comprobante_vino
  WHERE numero_comprobante = 'TST-COMP-RN' AND codigo_vino = 'TST-WINE-RN';
  SELECT total INTO v_total FROM bodegas_atuel.comprobante
  WHERE numero_comprobante = 'TST-COMP-RN';
  SELECT cantidad_stock INTO v_stock FROM bodegas_atuel.stock_sala
  WHERE id_sala = 2100000011 AND codigo_vino = 'TST-WINE-RN';
  IF v_total <> 0 OR v_stock <> 10 THEN
    RAISE EXCEPTION 'DELETE de renglón no revirtió total/stock: %, %', v_total, v_stock;
  END IF;
  RAISE NOTICE 'OK RN-08/RN-09: INSERT/UPDATE/DELETE de venta';

  INSERT INTO bodegas_atuel.comprobante_vino
    (numero_comprobante, codigo_vino, cantidad, precio)
  VALUES ('TST-COMP-RN', 'TST-WINE-RN', 2, 100);
  PERFORM set_config('bodegas.eliminando_comprobante', 'on', true);
  DELETE FROM bodegas_atuel.comprobante_vino
  WHERE numero_comprobante = 'TST-COMP-RN' AND codigo_vino = 'TST-WINE-RN';
  PERFORM set_config('bodegas.eliminando_comprobante', 'off', true);
  SELECT cantidad_stock INTO v_stock
  FROM bodegas_atuel.stock_sala
  WHERE id_sala = 2100000011 AND codigo_vino = 'TST-WINE-RN';
  IF v_stock <> 10 THEN
    RAISE EXCEPTION 'Una GUC manipulada omitió el reintegro de stock: %', v_stock;
  END IF;
  RAISE NOTICE 'OK: GUC de sesión no puede omitir actualización de stock';

  INSERT INTO bodegas_atuel.comprobante
    (numero_comprobante, fecha, id_cliente, id_sala, descuento_aplicado, total)
  VALUES ('TST-COMP-DEL', CURRENT_DATE, 2100000012, 2100000011, 0, 0);
  INSERT INTO bodegas_atuel.comprobante_vino
    (numero_comprobante, codigo_vino, cantidad, precio)
  VALUES ('TST-COMP-DEL', 'TST-WINE-RN', 3, 100);
  BEGIN
    DELETE FROM bodegas_atuel.comprobante
    WHERE numero_comprobante = 'TST-COMP-DEL';
    RAISE EXCEPTION 'Borrado de comprobante con renglones aceptado' USING ERRCODE = 'P0001';
  EXCEPTION WHEN foreign_key_violation OR restrict_violation THEN
    RAISE NOTICE 'OK política actual: comprobante con renglones no se puede borrar';
  END;
  SELECT cantidad_stock INTO v_stock
  FROM bodegas_atuel.stock_sala
  WHERE id_sala = 2100000011 AND codigo_vino = 'TST-WINE-RN';
  IF v_stock <> 7
     OR NOT EXISTS (SELECT 1 FROM bodegas_atuel.comprobante_vino
                    WHERE numero_comprobante = 'TST-COMP-DEL') THEN
    RAISE EXCEPTION 'Un borrado rechazado alteró el detalle o el stock: %', v_stock;
  END IF;
  DELETE FROM bodegas_atuel.comprobante_vino
  WHERE numero_comprobante = 'TST-COMP-DEL';
  DELETE FROM bodegas_atuel.comprobante
  WHERE numero_comprobante = 'TST-COMP-DEL';
  SELECT cantidad_stock INTO v_stock
  FROM bodegas_atuel.stock_sala
  WHERE id_sala = 2100000011 AND codigo_vino = 'TST-WINE-RN';
  IF v_stock <> 10 THEN
    RAISE EXCEPTION 'El borrado del renglón no reintegró stock una sola vez: %', v_stock;
  END IF;
  RAISE NOTICE 'OK: el detalle devuelve stock y el comprobante vacío se puede borrar';

  -- La modificación vigente no cambia la tasa ni total históricos; U1 también usa historia.
  PERFORM bodegas_atuel.fn_recalcular_totales_comprobantes();
  SELECT descuento_aplicado, total INTO v_valor, v_total
  FROM bodegas_atuel.comprobante WHERE numero_comprobante = 'TST-COMP-RN';
  IF v_valor <> 30 OR v_total <> 0 THEN
    RAISE EXCEPTION 'U1 modificó el descuento/total histórico';
  END IF;
  RAISE NOTICE 'OK: U1 recalcula con tasa histórica y no cambia descuentos';

  -- RN-10: ingreso en confección no afecta stock; procesar terminado una sola vez.
  INSERT INTO bodegas_atuel.ingreso
    (codigo_ingreso, fecha, codigo_transporte, cuit_bodega)
  VALUES ('TST-ING-RN', CURRENT_DATE, 'TST-TRANS-01', '20234567891');
  INSERT INTO bodegas_atuel.ingreso_vino
    (codigo_ingreso, codigo_vino, cantidad_botellas)
  VALUES ('TST-ING-RN', 'TST-WINE-RN', 5);
  IF (SELECT cantidad_botellas_disponibles FROM bodegas_atuel.stock_deposito
      WHERE codigo_vino = 'TST-WINE-RN') <> 0 THEN
    RAISE EXCEPTION 'Ingreso en confección impactó el stock';
  END IF;
  UPDATE bodegas_atuel.ingreso SET estado = 'terminado'
  WHERE codigo_ingreso = 'TST-ING-RN';
  CALL bodegas_atuel.sp_procesar_ingreso('TST-ING-RN');
  IF (SELECT cantidad_botellas_disponibles FROM bodegas_atuel.stock_deposito
      WHERE codigo_vino = 'TST-WINE-RN') <> 5 THEN
    RAISE EXCEPTION 'Ingreso procesado no acreditó stock';
  END IF;
  BEGIN
    CALL bodegas_atuel.sp_procesar_ingreso('TST-ING-RN');
    RAISE EXCEPTION 'Ingreso procesado dos veces aceptado' USING ERRCODE = 'P0001';
  EXCEPTION WHEN invalid_parameter_value THEN
    RAISE NOTICE 'OK RN-10: ingreso aplicado una sola vez';
  END;
  BEGIN
    DELETE FROM bodegas_atuel.ingreso
    WHERE codigo_ingreso = 'TST-ING-RN';
    RAISE EXCEPTION 'Borrado de ingreso procesado aceptado' USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK política actual: ingreso procesado reciente conserva su historial';
  END;

  -- RN-11: transferencia debita depósito y acredita sala; segunda aplicación se rechaza.
  INSERT INTO bodegas_atuel.transferencia (numero_solicitud, id_sala)
  VALUES ('TST-TR-RN', 2100000011);
  INSERT INTO bodegas_atuel.transferencia_vino
    (numero_solicitud, codigo_vino, cantidad_botellas)
  VALUES ('TST-TR-RN', 'TST-WINE-RN', 3);
  UPDATE bodegas_atuel.transferencia SET estado = 'terminado'
  WHERE numero_solicitud = 'TST-TR-RN';
  CALL bodegas_atuel.sp_procesar_transferencia('TST-TR-RN');
  IF (SELECT cantidad_botellas_disponibles FROM bodegas_atuel.stock_deposito
      WHERE codigo_vino = 'TST-WINE-RN') <> 2
     OR (SELECT cantidad_stock FROM bodegas_atuel.stock_sala
         WHERE id_sala = 2100000011 AND codigo_vino = 'TST-WINE-RN') <> 13 THEN
    RAISE EXCEPTION 'Transferencia no actualizó ambos stocks';
  END IF;
  BEGIN
    CALL bodegas_atuel.sp_procesar_transferencia('TST-TR-RN');
    RAISE EXCEPTION 'Transferencia procesada dos veces aceptada' USING ERRCODE = 'P0001';
  EXCEPTION WHEN invalid_parameter_value THEN
    RAISE NOTICE 'OK RN-11: transferencia aplicada una sola vez';
  END;
  BEGIN
    DELETE FROM bodegas_atuel.transferencia
    WHERE numero_solicitud = 'TST-TR-RN';
    RAISE EXCEPTION 'Borrado de transferencia procesada aceptado' USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK política actual: transferencia procesada conserva su historial';
  END;

  -- RN-12: documentos procesados no permiten modificar renglones.
  BEGIN
    UPDATE bodegas_atuel.ingreso_vino SET cantidad_botellas = 6
    WHERE codigo_ingreso = 'TST-ING-RN' AND codigo_vino = 'TST-WINE-RN';
    RAISE EXCEPTION 'Renglón de ingreso procesado modificable' USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK RN-12: renglón procesado inmutable';
  END;

  -- RN-13: auditar cambios efectivos de precio, no escrituras del mismo valor.
  SELECT COUNT(*) INTO v_auditorias FROM bodegas_atuel.auditoria_precios
  WHERE codigo_vino = 'TST-WINE-RN';
  PERFORM set_config('bodegas.usuario_responsable', 'usuario_falso', true);
  UPDATE bodegas_atuel.vino SET precio = 110 WHERE codigo_vino = 'TST-WINE-RN';
  UPDATE bodegas_atuel.vino SET precio = 110 WHERE codigo_vino = 'TST-WINE-RN';
  SELECT usuario_modificacion INTO v_usuario
  FROM bodegas_atuel.auditoria_precios
  WHERE codigo_vino = 'TST-WINE-RN'
  ORDER BY id_auditoria DESC
  LIMIT 1;
  IF (SELECT COUNT(*) FROM bodegas_atuel.auditoria_precios
      WHERE codigo_vino = 'TST-WINE-RN') <> v_auditorias + 1
     OR v_usuario <> session_user THEN
    RAISE EXCEPTION 'Auditoría de precio no registró exactamente un cambio efectivo';
  END IF;
  PERFORM set_config('bodegas.usuario_responsable', 'off', true);
  RAISE NOTICE 'OK RN-13: auditoría de cambio efectivo';

  -- RN-14: restringir borrado de vino con movimientos/composición asociados.
  BEGIN
    DELETE FROM bodegas_atuel.vino WHERE codigo_vino = 'TST-WINE-RN';
    RAISE EXCEPTION 'Borrado de vino referenciado aceptado' USING ERRCODE = 'P0001';
  EXCEPTION WHEN foreign_key_violation OR restrict_violation THEN
    RAISE NOTICE 'OK RN-14: borrado de vino referenciado restringido';
  END;

  -- RN-15: valores positivos de cantidades y medidas.
  BEGIN
    INSERT INTO bodegas_atuel.stock_sala (id_sala, codigo_vino, cantidad_stock)
    VALUES (2100000011, 'TST-WINE-RN', -1);
    RAISE EXCEPTION 'Stock negativo aceptado' USING ERRCODE = 'P0001';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK RN-15: stock negativo rechazado';
  END;
END;
$$;

-- Fase B: defectos de integridad. Las excepciones de prueba usan P0001 para
-- no confundirse con el rechazo 23514/42501 que se espera del esquema.
DO $$
DECLARE
  v_nombre text;
  v_sql text;
BEGIN
  -- H6: ni NULL ni blanco identifican al cliente; apellido no es obligatorio
  -- para las empresas (el exportador del fixture tiene apellido NULL).
  FOREACH v_nombre IN ARRAY ARRAY[NULL::text, '', '   '] LOOP
    BEGIN
      UPDATE bodegas_atuel.cliente SET nombre = v_nombre WHERE id_cliente = 2100000012;
      RAISE EXCEPTION 'Identidad nominal vacía aceptada';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
  END LOOP;
  IF (SELECT apellido FROM bodegas_atuel.cliente WHERE id_cliente = 2100000012) IS NOT NULL THEN
    RAISE EXCEPTION 'Fixture de empresa debe admitir apellido NULL';
  END IF;
  RAISE NOTICE 'OK H6: nombre obligatorio y empresa sin apellido';

  -- Totalidad: borrar el único subtipo no puede confirmarse.
  BEGIN
    DELETE FROM bodegas_atuel.socio WHERE id_cliente = 2100000011;
    SET CONSTRAINTS ALL IMMEDIATE;
    RAISE EXCEPTION 'Cliente sin subtipo aceptado';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  SET CONSTRAINTS ALL DEFERRED;
  -- Disyunción: no se puede añadir un segundo subtipo diferente.
  BEGIN
    INSERT INTO bodegas_atuel.exportador VALUES (2100000011, 'Chile');
    RAISE EXCEPTION 'Cliente con subtipo incompatible aceptado';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    UPDATE bodegas_atuel.cliente SET descuento = 35 WHERE id_cliente = 2100000011;
    RAISE EXCEPTION 'Descuento U6 de socio aceptado';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  RAISE NOTICE 'OK RN-06: ISA total/disjunta y descuento no elegible rechazados';

  -- H2: se prueban todos los atributos de cada cabecera procesada, incluidas
  -- sus claves. Los cambios deben fallar antes de cualquier efecto en stock.
  FOREACH v_sql IN ARRAY ARRAY[
    'UPDATE bodegas_atuel.transferencia SET id_sala = 2100000012 WHERE numero_solicitud = ''TST-TR-RN''',
    'UPDATE bodegas_atuel.transferencia SET fecha_confeccion = fecha_confeccion - 1 WHERE numero_solicitud = ''TST-TR-RN''',
    'UPDATE bodegas_atuel.transferencia SET estado = ''terminado'' WHERE numero_solicitud = ''TST-TR-RN''',
    'UPDATE bodegas_atuel.transferencia SET numero_solicitud = ''TST-TR-OTRA'' WHERE numero_solicitud = ''TST-TR-RN''',
    'UPDATE bodegas_atuel.ingreso SET fecha = fecha - 1 WHERE codigo_ingreso = ''TST-ING-RN''',
    'UPDATE bodegas_atuel.ingreso SET cuit_bodega = ''20999999999'' WHERE codigo_ingreso = ''TST-ING-RN''',
    'UPDATE bodegas_atuel.ingreso SET codigo_transporte = ''TST-OTRO'' WHERE codigo_ingreso = ''TST-ING-RN''',
    'UPDATE bodegas_atuel.ingreso SET estado = ''terminado'' WHERE codigo_ingreso = ''TST-ING-RN''',
    'UPDATE bodegas_atuel.ingreso SET codigo_ingreso = ''TST-ING-OTRO'' WHERE codigo_ingreso = ''TST-ING-RN'''
  ] LOOP
    BEGIN
      EXECUTE v_sql;
      RAISE EXCEPTION 'Cabecera procesada modificable: %', v_sql;
    EXCEPTION WHEN check_violation THEN NULL;
    END;
  END LOOP;
  IF (SELECT cantidad_botellas_disponibles FROM bodegas_atuel.stock_deposito
      WHERE codigo_vino = 'TST-WINE-RN') IS DISTINCT FROM 2
     OR (SELECT cantidad_stock FROM bodegas_atuel.stock_sala
         WHERE id_sala = 2100000011 AND codigo_vino = 'TST-WINE-RN') IS DISTINCT FROM 13
     OR EXISTS (SELECT 1 FROM bodegas_atuel.stock_sala
                WHERE id_sala = 2100000012 AND codigo_vino = 'TST-WINE-RN') THEN
    RAISE EXCEPTION 'Una modificación rechazada cambió el stock';
  END IF;
  RAISE NOTICE 'OK H2: cabeceras procesadas inmutables y stock intacto';
END;
$$;

-- H7: SET ROLE permite verificar ACL efectivas sin crear cuentas en el proyecto.
SET LOCAL ROLE bodegas_api;
SET LOCAL search_path = pg_temp;
DO $$
DECLARE
  v_sql text;
BEGIN
  -- Las funciones deben resolver objetos propios sin depender del search_path
  -- de la conexión. El rol puede usarlas, pero no escribir saldos ni auditoría.
  IF bodegas_atuel.fn_stock_sala(2100000011, 'TST-WINE-RN') IS DISTINCT FROM 13
     OR bodegas_atuel.fn_descuento_cliente(2100000011) IS DISTINCT FROM 10 THEN
    RAISE EXCEPTION 'Función API con search_path ajeno dio resultado incorrecto';
  END IF;
  FOREACH v_sql IN ARRAY ARRAY[
    'UPDATE bodegas_atuel.stock_sala SET cantidad_stock = 999 WHERE codigo_vino = ''TST-WINE-RN''',
    'INSERT INTO bodegas_atuel.stock_deposito VALUES (''PROHIBIDO'', 1)',
    'DELETE FROM bodegas_atuel.auditoria_precios',
    'UPDATE bodegas_atuel.comprobante SET total = 999 WHERE numero_comprobante = ''TST-COMP-RN''',
    'CREATE TABLE bodegas_atuel.no_autorizada (id integer)',
    'SELECT bodegas_atuel.fn_recalcular_total_comprobante(''TST-COMP-RN'')'
  ] LOOP
    BEGIN
      EXECUTE v_sql;
      RAISE EXCEPTION 'Permiso excesivo de API: %', v_sql;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;

  -- Venta histórica no vacía, U6 y U1 con ambos roles de uso previstos.
  BEGIN
    UPDATE bodegas_atuel.transferencia SET id_sala = 2100000012
    WHERE numero_solicitud = 'TST-TR-RN';
    RAISE EXCEPTION 'API modificó transferencia procesada';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF bodegas_atuel.fn_stock_sala(2100000011, 'TST-WINE-RN') IS DISTINCT FROM 13 THEN
    RAISE EXCEPTION 'Cambio rechazado de API alteró stock';
  END IF;
  UPDATE bodegas_atuel.cliente SET descuento = 30 WHERE id_cliente = 2100000012;
  INSERT INTO bodegas_atuel.comprobante
    (numero_comprobante, fecha, id_cliente, id_sala)
  VALUES ('TST-HIST-B', CURRENT_DATE, 2100000012, 2100000011);
  INSERT INTO bodegas_atuel.comprobante_vino VALUES ('TST-HIST-B', 'TST-WINE-RN', 2, 100);
  UPDATE bodegas_atuel.cliente SET descuento = 35
  WHERE id_cliente = 2100000012
    AND (SELECT COUNT(*) FROM bodegas_atuel.permiso_exportacion
         WHERE id_exportador = 2100000012) > 3;
  PERFORM bodegas_atuel.fn_recalcular_totales_comprobantes();
  IF (SELECT total FROM bodegas_atuel.comprobante WHERE numero_comprobante = 'TST-HIST-B') IS DISTINCT FROM 140
     OR (SELECT descuento_aplicado FROM bodegas_atuel.comprobante WHERE numero_comprobante = 'TST-HIST-B') IS DISTINCT FROM 30 THEN
    RAISE EXCEPTION 'U1/U6 modificaron una venta histórica no vacía';
  END IF;
  INSERT INTO bodegas_atuel.comprobante (numero_comprobante, fecha, id_cliente, id_sala)
  VALUES ('TST-NUEVA-B', CURRENT_DATE, 2100000012, 2100000011);
  INSERT INTO bodegas_atuel.comprobante_vino VALUES ('TST-NUEVA-B', 'TST-WINE-RN', 2, 100);
  IF (SELECT total FROM bodegas_atuel.comprobante WHERE numero_comprobante = 'TST-NUEVA-B') IS DISTINCT FROM 130 THEN
    RAISE EXCEPTION 'Venta nueva no usó descuento vigente del 35 %%';
  END IF;
  BEGIN
    INSERT INTO bodegas_atuel.comprobante_vino VALUES ('TST-COMP-RN', 'TST-WINE-RN', 999, 100);
    RAISE EXCEPTION 'Venta sin stock aceptada';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF bodegas_atuel.fn_stock_sala(2100000011, 'TST-WINE-RN') IS DISTINCT FROM 9
     OR EXISTS (SELECT 1 FROM bodegas_atuel.comprobante_vino WHERE numero_comprobante = 'TST-COMP-RN') THEN
    RAISE EXCEPTION 'Venta rechazada dejó cambios parciales';
  END IF;
  RAISE NOTICE 'OK API: funciones, permisos, U1/U6 histórico/nuevo y venta sin stock';
END;
$$;
RESET ROLE;

SET LOCAL ROLE bodegas_propietario;
-- Objeto de prueba transaccional: desaparece con el ROLLBACK de la suite.
CREATE FUNCTION bodegas_atuel.prueba_acl_fase_b() RETURNS integer
LANGUAGE sql AS 'SELECT 1';
DO $$
BEGIN
  IF has_function_privilege('bodegas_api', 'bodegas_atuel.prueba_acl_fase_b()', 'EXECUTE')
     OR has_function_privilege('bodegas_reportes', 'bodegas_atuel.prueba_acl_fase_b()', 'EXECUTE') THEN
    RAISE EXCEPTION 'Rutina nueva expuesta a PUBLIC por defaults incorrectos';
  END IF;
  -- El dueño puede ejecutar DML, pero no falsear el agregado mediante DML.
  BEGIN
    UPDATE bodegas_atuel.comprobante SET total = -1 WHERE numero_comprobante = 'TST-HIST-B';
    RAISE EXCEPTION 'Total manual inconsistente aceptado';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  UPDATE bodegas_atuel.comprobante_vino SET cantidad = 3
  WHERE numero_comprobante = 'TST-HIST-B' AND codigo_vino = 'TST-WINE-RN';
  IF (SELECT total FROM bodegas_atuel.comprobante WHERE numero_comprobante = 'TST-HIST-B') IS DISTINCT FROM 210 THEN
    RAISE EXCEPTION 'UPDATE de detalle no recalculó total protegido';
  END IF;
  DELETE FROM bodegas_atuel.comprobante_vino WHERE numero_comprobante = 'TST-HIST-B';
  IF (SELECT total FROM bodegas_atuel.comprobante WHERE numero_comprobante = 'TST-HIST-B') IS DISTINCT FROM 0
     OR bodegas_atuel.fn_stock_sala(2100000011, 'TST-WINE-RN') IS DISTINCT FROM 11 THEN
    RAISE EXCEPTION 'DELETE de detalle no recalculó total/stock';
  END IF;
  RAISE NOTICE 'OK H3: dueño rechaza total falso y mantiene UPDATE/DELETE de detalles';
END;
$$;
RESET ROLE;

-- Segundo vino sin existencias: el primer débito debe revertirse al fallar
-- el segundo. Se prueba como API, también el permiso de CALL real.
SET LOCAL ROLE bodegas_api;
INSERT INTO bodegas_atuel.vino
  (codigo_vino, nombre_comercial, tipo, anada, presentacion_ml,
   graduacion_alcoholica, precio, cuit_bodega)
VALUES ('TST-WINE-ZZZ', 'Segundo vino fase B', 'tinto', 2024, 750, 13, 100, '20234567891');
INSERT INTO bodegas_atuel.composicion_vino_cepa VALUES ('TST-WINE-ZZZ', 2100000011, 100);
INSERT INTO bodegas_atuel.transferencia (numero_solicitud, id_sala)
VALUES ('TST-ATOMIC-B', 2100000011);
INSERT INTO bodegas_atuel.transferencia_vino VALUES
  ('TST-ATOMIC-B', 'TST-WINE-RN', 1), ('TST-ATOMIC-B', 'TST-WINE-ZZZ', 1);
UPDATE bodegas_atuel.transferencia SET estado = 'terminado' WHERE numero_solicitud = 'TST-ATOMIC-B';
DO $$
BEGIN
  BEGIN
    CALL bodegas_atuel.sp_procesar_transferencia('TST-ATOMIC-B');
    RAISE EXCEPTION 'Transferencia sin stock aceptada';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF (SELECT cantidad_botellas_disponibles FROM bodegas_atuel.stock_deposito WHERE codigo_vino = 'TST-WINE-RN') IS DISTINCT FROM 2
     OR bodegas_atuel.fn_stock_sala(2100000011, 'TST-WINE-RN') IS DISTINCT FROM 11
     OR EXISTS (SELECT 1 FROM bodegas_atuel.stock_sala WHERE codigo_vino = 'TST-WINE-ZZZ')
     OR (SELECT estado::text FROM bodegas_atuel.transferencia WHERE numero_solicitud = 'TST-ATOMIC-B') IS DISTINCT FROM 'terminado' THEN
    RAISE EXCEPTION 'Transferencia fallida dejó efectos parciales';
  END IF;
  -- Éxitos con API: el ingreso aprovisiona y la transferencia después se procesa.
  INSERT INTO bodegas_atuel.ingreso (codigo_ingreso, fecha, codigo_transporte, cuit_bodega)
  VALUES ('TST-API-ING-B', CURRENT_DATE, 'TST-TRANS-01', '20234567891');
  INSERT INTO bodegas_atuel.ingreso_vino VALUES ('TST-API-ING-B', 'TST-WINE-ZZZ', 1);
  UPDATE bodegas_atuel.ingreso SET estado = 'terminado' WHERE codigo_ingreso = 'TST-API-ING-B';
  CALL bodegas_atuel.sp_procesar_ingreso('TST-API-ING-B');
  CALL bodegas_atuel.sp_procesar_transferencia('TST-ATOMIC-B');
  IF (SELECT estado::text FROM bodegas_atuel.transferencia WHERE numero_solicitud = 'TST-ATOMIC-B') IS DISTINCT FROM 'procesado'
     OR bodegas_atuel.fn_stock_sala(2100000011, 'TST-WINE-RN') IS DISTINCT FROM 12
     OR bodegas_atuel.fn_stock_sala(2100000011, 'TST-WINE-ZZZ') IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'Procesamiento válido como API incorrecto';
  END IF;
  RAISE NOTICE 'OK API: atomicidad multirrenglón y CALL válidos de ambos procedimientos';
END;
$$;
RESET ROLE;

SET LOCAL ROLE bodegas_reportes;
DO $$
BEGIN
  PERFORM * FROM bodegas_atuel.vw_stock_total_vino;
  PERFORM * FROM bodegas_atuel.vw_ventas_mensuales_sala;
  PERFORM * FROM bodegas_atuel.vw_documentos_pendientes;
  BEGIN
    DELETE FROM bodegas_atuel.stock_sala;
    RAISE EXCEPTION 'Reportes pudo modificar datos';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    CALL bodegas_atuel.sp_procesar_ingreso('TST-API-ING-B');
    RAISE EXCEPTION 'Reportes pudo ejecutar proceso de escritura';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'OK reportes: tres vistas accesibles, escritura y CALL denegados';
END;
$$;
RESET ROLE;

-- B.2: criterios estrictos, cascadas y conservación del inventario. Se ejecuta
-- como API: no tiene permisos para corregir saldos ni desactivar triggers.
SET LOCAL ROLE bodegas_api;
INSERT INTO bodegas_atuel.comprobante
  (numero_comprobante, fecha, id_cliente, id_sala)
VALUES
  ('TST-B2-D1-OLD', (CURRENT_DATE - INTERVAL '5 years')::date - 1, 2100000011, 2100000011),
  ('TST-B2-D1-LIMIT', (CURRENT_DATE - INTERVAL '5 years')::date, 2100000011, 2100000011),
  ('TST-B2-D1-NEW', CURRENT_DATE, 2100000011, 2100000011),
  ('TST-B2-D1-OTHER', (CURRENT_DATE - INTERVAL '6 years')::date, 2100000012, 2100000011);
INSERT INTO bodegas_atuel.comprobante_vino VALUES
  ('TST-B2-D1-OLD', 'TST-WINE-RN', 2, 100),
  ('TST-B2-D1-LIMIT', 'TST-WINE-RN', 3, 100),
  ('TST-B2-D1-NEW', 'TST-WINE-RN', 1, 100),
  ('TST-B2-D1-OTHER', 'TST-WINE-RN', 1, 100);

INSERT INTO bodegas_atuel.ingreso (codigo_ingreso, fecha, codigo_transporte, cuit_bodega)
VALUES
  ('TST-B2-D5-OLD', CURRENT_DATE - 366, 'TST-TRANS-01', '20234567891'),
  ('TST-B2-D5-LIMIT', CURRENT_DATE - 365, 'TST-TRANS-01', '20234567891'),
  ('TST-B2-D5-NEW', CURRENT_DATE - 364, 'TST-TRANS-01', '20234567891'),
  ('TST-B2-D5-TERM', CURRENT_DATE - 400, 'TST-TRANS-01', '20234567891'),
  ('TST-B2-D5-DRAFT', CURRENT_DATE - 400, 'TST-TRANS-01', '20234567891');
INSERT INTO bodegas_atuel.ingreso_vino VALUES
  ('TST-B2-D5-OLD', 'TST-WINE-RN', 2),
  ('TST-B2-D5-LIMIT', 'TST-WINE-RN', 3),
  ('TST-B2-D5-NEW', 'TST-WINE-RN', 4),
  ('TST-B2-D5-TERM', 'TST-WINE-RN', 5),
  ('TST-B2-D5-DRAFT', 'TST-WINE-RN', 6);
UPDATE bodegas_atuel.ingreso SET estado = 'terminado'
WHERE codigo_ingreso LIKE 'TST-B2-D5-%' AND codigo_ingreso <> 'TST-B2-D5-DRAFT';
CALL bodegas_atuel.sp_procesar_ingreso('TST-B2-D5-OLD');
CALL bodegas_atuel.sp_procesar_ingreso('TST-B2-D5-LIMIT');
CALL bodegas_atuel.sp_procesar_ingreso('TST-B2-D5-NEW');

DO $$
DECLARE
  v_salas jsonb;
  v_deposito jsonb;
  v_filas integer;
  v_codigo text;
BEGIN
  SELECT jsonb_agg(to_jsonb(s) ORDER BY id_sala, codigo_vino) INTO v_salas
  FROM bodegas_atuel.stock_sala s;
  SELECT jsonb_agg(to_jsonb(s) ORDER BY codigo_vino) INTO v_deposito
  FROM bodegas_atuel.stock_deposito s;

  -- Forzar un fallo DESPUÉS de borrar prueba rollback de ambas cascadas.
  BEGIN
    DELETE FROM bodegas_atuel.comprobante WHERE numero_comprobante = 'TST-B2-D1-OLD';
    DELETE FROM bodegas_atuel.ingreso WHERE codigo_ingreso = 'TST-B2-D5-OLD';
    INSERT INTO bodegas_atuel.stock_sala VALUES (2100000011, 'TST-WINE-RN', 999);
    RAISE EXCEPTION 'API obtuvo permiso inesperado para escribir stock';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  IF NOT EXISTS (SELECT 1 FROM bodegas_atuel.comprobante_vino WHERE numero_comprobante = 'TST-B2-D1-OLD')
     OR NOT EXISTS (SELECT 1 FROM bodegas_atuel.ingreso_vino WHERE codigo_ingreso = 'TST-B2-D5-OLD') THEN
    RAISE EXCEPTION 'Fallo posterior no revirtió cabeceras y detalles';
  END IF;

  -- GUC arbitraria no permite borrar cabeceras recientes ni renglones de
  -- ingresos procesados. Tampoco puede convertir una transferencia en D5.
  PERFORM set_config('bodegas.purga_historica', 'on', true);
  FOREACH v_codigo IN ARRAY ARRAY['TST-B2-D1-LIMIT', 'TST-B2-D1-NEW', 'TST-B2-D1-OTHER'] LOOP
    BEGIN
      DELETE FROM bodegas_atuel.comprobante WHERE numero_comprobante = v_codigo;
      RAISE EXCEPTION 'D1 admitió comprobante no elegible: %', v_codigo;
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
  END LOOP;
  FOREACH v_codigo IN ARRAY ARRAY['TST-B2-D5-LIMIT', 'TST-B2-D5-NEW', 'TST-B2-D5-TERM'] LOOP
    BEGIN
      DELETE FROM bodegas_atuel.ingreso WHERE codigo_ingreso = v_codigo;
      RAISE EXCEPTION 'D5 admitió ingreso no elegible: %', v_codigo;
    EXCEPTION WHEN check_violation THEN NULL;
    END;
  END LOOP;
  BEGIN
    DELETE FROM bodegas_atuel.ingreso_vino WHERE codigo_ingreso = 'TST-B2-D5-OLD';
    RAISE EXCEPTION 'Purga permitió DELETE directo de detalle procesado';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    DELETE FROM bodegas_atuel.transferencia WHERE numero_solicitud = 'TST-TR-RN';
    RAISE EXCEPTION 'Purga permitió DELETE de transferencia procesada';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  DELETE FROM bodegas_atuel.comprobante c USING bodegas_atuel.socio s
  WHERE s.id_cliente = c.id_cliente AND c.fecha < CURRENT_DATE - INTERVAL '5 years';
  GET DIAGNOSTICS v_filas = ROW_COUNT;
  IF v_filas <> 1 THEN RAISE EXCEPTION 'D1 debía borrar exactamente un comprobante, borró %', v_filas; END IF;
  DELETE FROM bodegas_atuel.ingreso
  WHERE estado = 'procesado' AND fecha < CURRENT_DATE - 365;
  GET DIAGNOSTICS v_filas = ROW_COUNT;
  IF v_filas <> 1 THEN RAISE EXCEPTION 'D5 debía borrar exactamente un ingreso, borró %', v_filas; END IF;

  IF EXISTS (SELECT 1 FROM bodegas_atuel.comprobante_vino WHERE numero_comprobante = 'TST-B2-D1-OLD')
     OR EXISTS (SELECT 1 FROM bodegas_atuel.ingreso_vino WHERE codigo_ingreso = 'TST-B2-D5-OLD')
     OR (SELECT count(*) FROM bodegas_atuel.comprobante WHERE numero_comprobante LIKE 'TST-B2-D1-%') <> 3
     OR (SELECT count(*) FROM bodegas_atuel.ingreso WHERE codigo_ingreso LIKE 'TST-B2-D5-%') <> 4 THEN
    RAISE EXCEPTION 'Purga dejó detalles o eliminó documentos ajenos al filtro';
  END IF;
  IF v_salas IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(s) ORDER BY id_sala, codigo_vino) FROM bodegas_atuel.stock_sala s)
     OR v_deposito IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(s) ORDER BY codigo_vino) FROM bodegas_atuel.stock_deposito s) THEN
    RAISE EXCEPTION 'D1/D5 o sus fallos modificaron existencias';
  END IF;
  RAISE NOTICE 'OK B.2: D1=1, D5=1; límites/exclusiones y rollback; stocks completos idénticos';

  -- La eliminación ordinaria de detalle conserva el reintegro, incluso con
  -- GUC falsa; confección conserva su DELETE normal, sin impacto de stock.
  DELETE FROM bodegas_atuel.comprobante_vino WHERE numero_comprobante = 'TST-B2-D1-NEW';
  IF bodegas_atuel.fn_stock_sala(2100000011, 'TST-WINE-RN') IS DISTINCT FROM 6
     OR (SELECT total FROM bodegas_atuel.comprobante WHERE numero_comprobante = 'TST-B2-D1-NEW') IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'DELETE ordinario de renglón no reintegró una botella/total';
  END IF;
  DELETE FROM bodegas_atuel.comprobante WHERE numero_comprobante = 'TST-B2-D1-NEW';
  DELETE FROM bodegas_atuel.ingreso WHERE codigo_ingreso = 'TST-B2-D5-DRAFT';
  IF EXISTS (SELECT 1 FROM bodegas_atuel.ingreso_vino WHERE codigo_ingreso = 'TST-B2-D5-DRAFT')
     OR v_deposito IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(s) ORDER BY codigo_vino) FROM bodegas_atuel.stock_deposito s) THEN
    RAISE EXCEPTION 'DELETE ordinario de ingreso en confección incorrecto';
  END IF;
  PERFORM set_config('bodegas.purga_historica', 'off', true);

  -- RN-14 sigue vigente mientras haya movimientos asociados conservados.
  BEGIN
    DELETE FROM bodegas_atuel.transportista WHERE codigo_transporte = 'TST-TRANS-01';
    RAISE EXCEPTION 'RN-14 permitió borrar transportista con ingresos';
  EXCEPTION WHEN foreign_key_violation OR restrict_violation THEN NULL;
  END;
  BEGIN
    DELETE FROM bodegas_atuel.bodega WHERE cuit = '20234567891';
    RAISE EXCEPTION 'RN-14 permitió borrar bodega con movimientos';
  EXCEPTION WHEN foreign_key_violation OR restrict_violation THEN NULL;
  END;
  RAISE NOTICE 'OK B.2: reversión ordinaria, confección y RN-14 conservadas; GUC no evade controles';
END;
$$;
RESET ROLE;

-- La ISA y composición deben continuar en un estado válido al cerrar la transacción.
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
