-- Perfil del generador, no reemplazo de las restricciones del esquema.
-- psql -X -v ON_ERROR_STOP=1 -v fecha_ref=2026-11-09 -f validar_carga.sql
-- No usa CURRENT_DATE: todos los controles temporales reciben la misma fecha.
CREATE TEMP VIEW controles_carga AS
WITH parametros AS (SELECT :'fecha_ref'::date AS fecha),
ingresado AS (
  SELECT iv.codigo_vino, SUM(iv.cantidad_botellas) AS cantidad
  FROM bodegas_atuel.ingreso i JOIN bodegas_atuel.ingreso_vino iv USING (codigo_ingreso)
  WHERE i.estado='procesado' GROUP BY iv.codigo_vino
), trasladado AS (
  SELECT t.id_sala, tv.codigo_vino, SUM(tv.cantidad_botellas) AS cantidad
  FROM bodegas_atuel.transferencia t JOIN bodegas_atuel.transferencia_vino tv USING (numero_solicitud)
  WHERE t.estado='procesado' GROUP BY t.id_sala,tv.codigo_vino
), vendido AS (
  SELECT c.id_sala, cv.codigo_vino, SUM(cv.cantidad) AS cantidad
  FROM bodegas_atuel.comprobante c JOIN bodegas_atuel.comprobante_vino cv USING (numero_comprobante)
  GROUP BY c.id_sala,cv.codigo_vino
), importes AS (
  SELECT numero_comprobante, SUM(cantidad::numeric*precio) AS bruto
  FROM bodegas_atuel.comprobante_vino GROUP BY numero_comprobante
), movimientos AS (
  SELECT t.id_sala,tv.codigo_vino,t.fecha_confeccion AS fecha,tv.cantidad_botellas::bigint AS cantidad
  FROM bodegas_atuel.transferencia t JOIN bodegas_atuel.transferencia_vino tv USING (numero_solicitud)
  WHERE t.estado='procesado'
  UNION ALL
  SELECT c.id_sala,cv.codigo_vino,c.fecha,-cv.cantidad::bigint
  FROM bodegas_atuel.comprobante c JOIN bodegas_atuel.comprobante_vino cv USING (numero_comprobante)
), saldo_diario AS (
  SELECT id_sala,codigo_vino,fecha,
    SUM(SUM(cantidad)) OVER (PARTITION BY id_sala,codigo_vino ORDER BY fecha) AS saldo
  FROM movimientos GROUP BY id_sala,codigo_vino,fecha
), central AS (
  SELECT iv.codigo_vino,i.fecha,iv.cantidad_botellas::bigint AS cantidad
  FROM bodegas_atuel.ingreso i JOIN bodegas_atuel.ingreso_vino iv USING (codigo_ingreso)
  WHERE i.estado='procesado'
  UNION ALL
  SELECT tv.codigo_vino,t.fecha_confeccion,-tv.cantidad_botellas::bigint
  FROM bodegas_atuel.transferencia t JOIN bodegas_atuel.transferencia_vino tv USING (numero_solicitud)
  WHERE t.estado='procesado'
), saldo_central AS (
  SELECT codigo_vino,fecha,SUM(SUM(cantidad)) OVER (PARTITION BY codigo_vino ORDER BY fecha) AS saldo
  FROM central GROUP BY codigo_vino,fecha
)
SELECT 'stock_sala_no_negativo' AS control, count(*) AS errores
FROM bodegas_atuel.stock_sala WHERE cantidad_stock<0
UNION ALL SELECT 'stock_deposito_no_negativo',count(*) FROM bodegas_atuel.stock_deposito WHERE cantidad_botellas_disponibles<0
UNION ALL SELECT 'conciliacion_deposito',count(*)
FROM bodegas_atuel.stock_deposito d LEFT JOIN ingresado i USING(codigo_vino)
LEFT JOIN (SELECT codigo_vino,SUM(cantidad) AS cantidad FROM trasladado GROUP BY codigo_vino) t USING(codigo_vino)
WHERE d.cantidad_botellas_disponibles<>COALESCE(i.cantidad,0)-COALESCE(t.cantidad,0)
UNION ALL SELECT 'conciliacion_salas',count(*)
FROM (SELECT id_sala,codigo_vino FROM trasladado UNION SELECT id_sala,codigo_vino FROM vendido
      UNION SELECT id_sala,codigo_vino FROM bodegas_atuel.stock_sala) claves
LEFT JOIN trasladado t USING(id_sala,codigo_vino) LEFT JOIN vendido v USING(id_sala,codigo_vino)
LEFT JOIN bodegas_atuel.stock_sala s USING(id_sala,codigo_vino)
WHERE COALESCE(s.cantidad_stock,0)<>COALESCE(t.cantidad,0)-COALESCE(v.cantidad,0)
UNION ALL SELECT 'saldo_historico_sala',count(*) FROM saldo_diario WHERE saldo<0
UNION ALL SELECT 'saldo_historico_deposito',count(*) FROM saldo_central WHERE saldo<0
UNION ALL SELECT 'composicion_100',count(*) FROM (
  SELECT v.codigo_vino FROM bodegas_atuel.vino v LEFT JOIN bodegas_atuel.composicion_vino_cepa c USING(codigo_vino)
  GROUP BY v.codigo_vino HAVING COALESCE(SUM(c.porcentaje_corte),0)<>100) x
UNION ALL SELECT 'isa_total_disjunta',count(*) FROM bodegas_atuel.cliente c
LEFT JOIN bodegas_atuel.socio s USING(id_cliente) LEFT JOIN bodegas_atuel.distribuidor d USING(id_cliente)
LEFT JOIN bodegas_atuel.exportador e USING(id_cliente)
WHERE (s.id_cliente IS NOT NULL)::int+(d.id_cliente IS NOT NULL)::int+(e.id_cliente IS NOT NULL)::int<>1
 OR (c.tipo_cliente='socio')<>(s.id_cliente IS NOT NULL)
 OR (c.tipo_cliente='distribuidor')<>(d.id_cliente IS NOT NULL)
 OR (c.tipo_cliente='exportador')<>(e.id_cliente IS NOT NULL)
UNION ALL SELECT 'totales',count(*) FROM bodegas_atuel.comprobante c LEFT JOIN importes i USING(numero_comprobante)
WHERE c.total<>ROUND(COALESCE(i.bruto,0)*(1-c.descuento_aplicado/100),2) OR i.numero_comprobante IS NULL
UNION ALL SELECT 'descuento_historico_perfil',count(*) FROM bodegas_atuel.comprobante c
JOIN bodegas_atuel.cliente cl USING(id_cliente) CROSS JOIN parametros p
WHERE c.descuento_aplicado<>CASE WHEN c.fecha<p.fecha-90 THEN
  CASE cl.tipo_cliente WHEN 'socio' THEN 10 WHEN 'distribuidor' THEN 20 ELSE 30 END ELSE cl.descuento END
UNION ALL SELECT 'descuento_vigente',count(*) FROM bodegas_atuel.cliente c
WHERE descuento<>CASE tipo_cliente WHEN 'socio' THEN 10 WHEN 'distribuidor' THEN 20
  ELSE CASE WHEN id_cliente%12=0 THEN 35 ELSE 30 END END
UNION ALL SELECT 'precio_historico_perfil',count(*) FROM bodegas_atuel.comprobante_vino cv
JOIN bodegas_atuel.comprobante c USING(numero_comprobante) CROSS JOIN parametros p
WHERE cv.precio<>(1000+substring(cv.codigo_vino FROM 2)::int*50)*CASE WHEN c.fecha<p.fecha-90 THEN 1 ELSE 1.10 END
UNION ALL SELECT 'fechas_venta',count(*) FROM bodegas_atuel.comprobante c
JOIN bodegas_atuel.cliente cl USING(id_cliente) CROSS JOIN parametros p
WHERE c.fecha>p.fecha OR c.fecha<cl.fecha_de_alta
UNION ALL SELECT 'anada_antes_venta',count(*) FROM bodegas_atuel.comprobante c
JOIN bodegas_atuel.comprobante_vino cv USING(numero_comprobante) JOIN bodegas_atuel.vino v USING(codigo_vino)
WHERE v.anada>EXTRACT(YEAR FROM c.fecha)
UNION ALL SELECT 'fechas_cosecha_analisis',count(*) FROM bodegas_atuel.lote_uva l
JOIN bodegas_atuel.analisis_calidad a USING(numero_lote) CROSS JOIN parametros p
WHERE EXTRACT(YEAR FROM l.fecha_cosecha)<>l.campania OR EXTRACT(MONTH FROM l.fecha_cosecha) NOT BETWEEN 2 AND 4
 OR a.fecha<l.fecha_cosecha OR a.fecha>p.fecha
UNION ALL SELECT 'fechas_movimientos',count(*) FROM (
 SELECT fecha FROM bodegas_atuel.ingreso UNION ALL SELECT fecha_confeccion FROM bodegas_atuel.transferencia) x
CROSS JOIN parametros p WHERE x.fecha>p.fecha
UNION ALL SELECT 'bodega_ingreso',count(*) FROM bodegas_atuel.ingreso i
JOIN bodegas_atuel.ingreso_vino iv USING(codigo_ingreso) JOIN bodegas_atuel.vino v USING(codigo_vino)
WHERE i.cuit_bodega<>v.cuit_bodega
UNION ALL SELECT 'permiso_vigente_al_corte',count(*) FROM bodegas_atuel.permiso_exportacion x CROSS JOIN parametros p
WHERE x.fecha_emision>p.fecha OR x.fecha_vencimiento<=p.fecha
UNION ALL SELECT 'valores_venta',count(*) FROM bodegas_atuel.comprobante_vino WHERE cantidad<=0 OR precio<=0
UNION ALL SELECT 'valores_vino',count(*) FROM bodegas_atuel.vino
WHERE precio<=0 OR graduacion_alcoholica NOT BETWEEN 5 AND 20 OR presentacion_ml<=0
UNION ALL SELECT 'triggers_activos',count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='bodegas_atuel' AND t.tgenabled<>'O'
UNION ALL SELECT 'constraints_validadas',count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace
WHERE n.nspname='bodegas_atuel' AND NOT c.convalidated
UNION ALL SELECT 'escenarios_ventas_periodos',CASE WHEN
 EXISTS(SELECT 1 FROM bodegas_atuel.comprobante c CROSS JOIN parametros p WHERE c.fecha>=p.fecha-7)
 AND EXISTS(SELECT 1 FROM bodegas_atuel.comprobante c JOIN bodegas_atuel.socio s USING(id_cliente) CROSS JOIN parametros p WHERE c.fecha<p.fecha-INTERVAL '5 years')
 AND EXISTS(SELECT 1 FROM bodegas_atuel.comprobante c WHERE c.descuento_aplicado=35)
 AND EXISTS(SELECT 1 FROM bodegas_atuel.comprobante c JOIN bodegas_atuel.cliente cl USING(id_cliente) WHERE c.descuento_aplicado<>cl.descuento)
 THEN 0 ELSE 1 END
UNION ALL SELECT 'escenarios_stock_movimientos',CASE WHEN
 EXISTS(SELECT 1 FROM bodegas_atuel.ingreso i CROSS JOIN parametros p WHERE estado='procesado' AND i.fecha<p.fecha-365)
 AND EXISTS(SELECT 1 FROM bodegas_atuel.ingreso i CROSS JOIN parametros p WHERE i.fecha>=p.fecha-30)
 AND EXISTS(SELECT 1 FROM bodegas_atuel.transferencia t CROSS JOIN parametros p WHERE fecha_confeccion>=p.fecha-15 AND estado<>'procesado')
 AND EXISTS(SELECT 1 FROM bodegas_atuel.stock_deposito d WHERE cantidad_botellas_disponibles>0 AND NOT EXISTS(SELECT 1 FROM bodegas_atuel.stock_sala s WHERE s.id_sala=1 AND s.codigo_vino=d.codigo_vino AND s.cantidad_stock>0))
 THEN 0 ELSE 1 END
UNION ALL SELECT 'escenarios_catalogos_personal',CASE WHEN
 EXISTS(SELECT 1 FROM bodegas_atuel.localidad WHERE nombre='General Alvear')
 AND EXISTS(SELECT 1 FROM bodegas_atuel.vino WHERE nombre_comercial='Malbec Reserva' AND presentacion_ml=750)
 AND EXISTS(SELECT 1 FROM bodegas_atuel.vino WHERE tipo='tinto' AND graduacion_alcoholica>=14)
 AND EXISTS(SELECT 1 FROM bodegas_atuel.empleado e CROSS JOIN parametros p WHERE fecha_laboral<p.fecha-INTERVAL '5 years')
 AND EXISTS(SELECT 1 FROM bodegas_atuel.empleado e CROSS JOIN parametros p WHERE fecha_laboral>p.fecha-INTERVAL '2 years')
 AND EXISTS(SELECT 1 FROM bodegas_atuel.socio s WHERE NOT EXISTS(SELECT 1 FROM bodegas_atuel.comprobante c WHERE c.id_cliente=s.id_cliente))
 AND EXISTS(SELECT 1 FROM bodegas_atuel.cepa c WHERE NOT EXISTS(SELECT 1 FROM bodegas_atuel.parcela p WHERE p.id_cepa=c.id_cepa) AND NOT EXISTS(SELECT 1 FROM bodegas_atuel.composicion_vino_cepa v WHERE v.id_cepa=c.id_cepa))
 THEN 0 ELSE 1 END
UNION ALL SELECT 'vino_todas_las_salas',CASE WHEN EXISTS(
 SELECT cv.codigo_vino FROM bodegas_atuel.comprobante c JOIN bodegas_atuel.comprobante_vino cv USING(numero_comprobante)
 GROUP BY cv.codigo_vino HAVING count(DISTINCT c.id_sala)=(SELECT count(*) FROM bodegas_atuel.sala_venta)) THEN 0 ELSE 1 END;

SELECT * FROM controles_carga ORDER BY control;
SELECT estado,count(*) AS ingresos FROM bodegas_atuel.ingreso GROUP BY estado ORDER BY estado;
SELECT estado,count(*) AS transferencias FROM bodegas_atuel.transferencia GROUP BY estado ORDER BY estado;
DO $$
DECLARE
  r record;
  v_filas bigint;
  v_grandes integer := 0;
  v_masiva boolean := false;
  v_hijas text;
  v_padres text;
  v_no_nulas text;
  v_fks integer := 0;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname='bodegas_atuel' ORDER BY tablename LOOP
    EXECUTE format('SELECT count(*) FROM bodegas_atuel.%I',r.tablename) INTO v_filas;
    RAISE NOTICE 'CONTEO %: %',r.tablename,v_filas;
    IF v_filas=0 THEN RAISE EXCEPTION 'Tabla vacía: %',r.tablename; END IF;
    IF v_filas>10000 THEN v_grandes:=v_grandes+1; END IF;
    v_masiva:=v_masiva OR v_filas>100000;
  END LOOP;
  IF v_grandes<3 OR NOT v_masiva THEN RAISE EXCEPTION 'No se cumplen mínimos de volumen'; END IF;
  -- Revisar las 35 FK mediante sus columnas reales, incluidas las compuestas.
  FOR r IN SELECT c.* FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace
           WHERE n.nspname='bodegas_atuel' AND c.contype='f' LOOP
    v_fks:=v_fks+1;
    SELECT string_agg(format('h.%I',a.attname),',' ORDER BY k.orden),
           string_agg(format('h.%I IS NOT NULL',a.attname),' AND ' ORDER BY k.orden)
    INTO v_hijas,v_no_nulas
    FROM unnest(r.conkey) WITH ORDINALITY k(num,orden)
    JOIN pg_attribute a ON a.attrelid=r.conrelid AND a.attnum=k.num;
    SELECT string_agg(format('p.%I',a.attname),',' ORDER BY k.orden) INTO v_padres
    FROM unnest(r.confkey) WITH ORDINALITY k(num,orden)
    JOIN pg_attribute a ON a.attrelid=r.confrelid AND a.attnum=k.num;
    EXECUTE format('SELECT count(*) FROM %s h WHERE %s AND NOT EXISTS (SELECT 1 FROM %s p WHERE (%s)=(%s))',
                   r.conrelid::regclass,v_no_nulas,r.confrelid::regclass,v_hijas,v_padres) INTO v_filas;
    IF v_filas<>0 THEN RAISE EXCEPTION 'Huérfanos en %: %',r.conname,v_filas; END IF;
  END LOOP;
  IF v_fks<>35 THEN RAISE EXCEPTION 'Se esperaban 35 FK, existen %',v_fks; END IF;
  FOR r IN SELECT c.* FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace
           WHERE n.nspname='bodegas_atuel' AND c.contype IN ('p','u') LOOP
    SELECT string_agg(format('%I',a.attname),',' ORDER BY k.orden) INTO v_hijas
    FROM unnest(r.conkey) WITH ORDINALITY k(num,orden)
    JOIN pg_attribute a ON a.attrelid=r.conrelid AND a.attnum=k.num;
    EXECUTE format('SELECT count(*) FROM (SELECT %s FROM %s GROUP BY %s HAVING count(*)>1) d',
                   v_hijas,r.conrelid::regclass,v_hijas) INTO v_filas;
    IF v_filas<>0 THEN RAISE EXCEPTION 'Duplicados en %',r.conname; END IF;
  END LOOP;
  IF EXISTS(SELECT 1 FROM controles_carga WHERE errores<>0) THEN
    RAISE EXCEPTION 'Hay controles de carga con errores';
  END IF;
  RAISE NOTICE 'OK: volumen, 35 FK, PK/UNIQUE y todos los controles ejecutados sin errores';
END;
$$;
DROP VIEW controles_carga;
