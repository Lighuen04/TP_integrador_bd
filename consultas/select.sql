\set ON_ERROR_STOP on
\set sala 1
\set sala_sin_stock 6
\set vino 'V001'
\set bodega '20200000001'
SET search_path TO bodegas_atuel, public;
-- Semana/15 días: siete/quince fechas incluyendo hoy. Mes/trimestre móviles:
-- desde hoy menos el intervalo hasta hoy inclusive, sin fechas futuras.

-- S1. Diez vinos más vendidos por botellas, no por número de renglones.
\echo S1
SELECT v.codigo_vino,v.nombre_comercial,sum(cv.cantidad) AS botellas
FROM vino v JOIN comprobante_vino cv USING(codigo_vino)
GROUP BY v.codigo_vino ORDER BY botellas DESC,v.codigo_vino LIMIT 10;

-- S2. División: no existe sala sin venta del vino. Sin salas, todo vino cumple.
\echo S2
SELECT v.codigo_vino,v.nombre_comercial FROM vino v WHERE NOT EXISTS (
 SELECT 1 FROM sala_venta s WHERE NOT EXISTS (
  SELECT 1 FROM comprobante c JOIN comprobante_vino cv USING(numero_comprobante)
  WHERE c.id_sala=s.id_sala AND cv.codigo_vino=v.codigo_vino
 )
) ORDER BY v.codigo_vino;

-- S3. Clientes distintos por tipo en la sala durante los siete días, incluido hoy.
-- ENUM permite mostrar cero para tipos sin compradores.
\echo S3
WITH compradores AS (
 SELECT cl.tipo_cliente,count(DISTINCT cl.id_cliente) AS cantidad
 FROM cliente cl JOIN comprobante c USING(id_cliente)
 WHERE c.id_sala=:sala AND c.fecha BETWEEN CURRENT_DATE-6 AND CURRENT_DATE GROUP BY cl.tipo_cliente
)
SELECT t.tipo,COALESCE(c.cantidad,0) AS clientes FROM unnest(enum_range(NULL::tipo_cliente)) t(tipo)
LEFT JOIN compradores c ON c.tipo_cliente=t.tipo ORDER BY t.tipo;

-- S4. Top cinco salas por unidades solicitadas del vino en los últimos 15 días.
-- Incluye todos los estados: solicitadas no significa solo procesadas.
\echo S4
SELECT t.id_sala,sum(tv.cantidad_botellas) AS botellas_solicitadas
FROM transferencia t JOIN transferencia_vino tv USING(numero_solicitud)
WHERE tv.codigo_vino=:'vino' AND t.fecha_confeccion BETWEEN CURRENT_DATE-14 AND CURRENT_DATE
GROUP BY t.id_sala ORDER BY botellas_solicitadas DESC,t.id_sala LIMIT 5;

-- S5. Todas las salas con el mínimo de pendientes, incluyendo cero y empates.
\echo S5
WITH pendientes AS (
 SELECT s.id_sala,count(t.numero_solicitud) AS cantidad FROM sala_venta s
 LEFT JOIN transferencia t ON t.id_sala=s.id_sala AND t.estado<>'procesado' GROUP BY s.id_sala
)
SELECT id_sala,cantidad FROM pendientes WHERE cantidad=(SELECT min(cantidad) FROM pendientes) ORDER BY id_sala;

-- S6. Stock cero o inexistente en sala 6, con existencias en depósito.
\echo S6
SELECT v.codigo_vino,v.nombre_comercial,d.cantidad_botellas_disponibles
FROM vino v JOIN stock_deposito d USING(codigo_vino)
LEFT JOIN stock_sala s ON s.codigo_vino=v.codigo_vino AND s.id_sala=:sala_sin_stock
WHERE COALESCE(s.cantidad_stock,0)=0 AND d.cantidad_botellas_disponibles>0 ORDER BY v.codigo_vino;

-- S7. Mayor actividad = número de ingresos asociados en el último mes.
-- Transferencias no tienen transportista. Empate: código ascendente.
\echo S7
SELECT t.codigo_transporte,t.razon_social,count(i.codigo_ingreso) AS ingresos
FROM transportista t JOIN ingreso i USING(codigo_transporte)
WHERE i.fecha>=CURRENT_DATE-INTERVAL '1 month' AND i.fecha<CURRENT_DATE+1
GROUP BY t.codigo_transporte ORDER BY ingresos DESC,t.codigo_transporte LIMIT 1;

-- S8. Ventas por sala del trimestre móvil, usando totales históricos almacenados.
\echo S8
SELECT s.id_sala,COALESCE(sum(c.total),0) AS total_ventas FROM sala_venta s
LEFT JOIN comprobante c ON c.id_sala=s.id_sala AND c.fecha>=CURRENT_DATE-INTERVAL '3 months' AND c.fecha<CURRENT_DATE+1
GROUP BY s.id_sala ORDER BY total_ventas DESC,s.id_sala;

-- S9. Ficha con asociaciones agregadas por separado, sin multiplicación N:M.
\echo S9
SELECT v.codigo_vino,v.nombre_comercial,v.tipo,v.anada,v.presentacion_ml,v.precio,b.razon_social AS bodega,
 (SELECT jsonb_agg(jsonb_build_object('cepa',c.nombre,'porcentaje',vc.porcentaje_corte) ORDER BY c.id_cepa)
  FROM composicion_vino_cepa vc JOIN cepa c USING(id_cepa) WHERE vc.codigo_vino=v.codigo_vino) AS composicion,
 (SELECT jsonb_agg(jsonb_build_object('maridaje',m.nombre,'temperatura',m.temperatura_servicio) ORDER BY m.id_maridaje)
  FROM vino_maridaje vm JOIN maridaje m USING(id_maridaje) WHERE vm.codigo_vino=v.codigo_vino) AS maridajes,
 st.cantidad_total_disponible AS stock_total
FROM vino v JOIN bodega b ON b.cuit=v.cuit_bodega JOIN vw_stock_total_vino st USING(codigo_vino)
WHERE v.codigo_vino=:'vino';

-- S10. Kg/ha por parcela/campaña, identificando valores bajo el promedio de finca.
-- Promedio simple de parcelas en la misma campaña, sin mezclar años.
\echo S10
WITH rendimientos AS (
 SELECT l.id_finca,l.numero_parcela,l.campania,l.kilos_cosechados/p.superficie_total AS kg_ha
 FROM lote_uva l JOIN parcela p USING(id_finca,numero_parcela)
), comparacion AS (
 SELECT r.*,(SELECT avg(o.kg_ha) FROM rendimientos o WHERE o.id_finca=r.id_finca AND o.campania=r.campania) AS promedio
 FROM rendimientos r
)
SELECT id_finca,numero_parcela,campania,ROUND(kg_ha,2) AS kg_ha,
ROUND(promedio,2) AS promedio_finca,kg_ha<promedio AS bajo_promedio
FROM comparacion ORDER BY id_finca,campania,numero_parcela;

-- S11. Dos resultados: ranking de vinos vendidos por sala y acumulado mensual.
-- RANK conserva empates; código ordena solo la presentación.
\echo S11_A
WITH ventas AS (
 SELECT c.id_sala,cv.codigo_vino,sum(cv.cantidad) AS botellas
 FROM comprobante c JOIN comprobante_vino cv USING(numero_comprobante) GROUP BY c.id_sala,cv.codigo_vino
)
SELECT id_sala,codigo_vino,botellas,RANK() OVER(PARTITION BY id_sala ORDER BY botellas DESC) AS puesto
FROM ventas ORDER BY id_sala,puesto,codigo_vino;
\echo S11_B
SELECT id_sala,mes,total_ventas,
sum(total_ventas) OVER(PARTITION BY id_sala ORDER BY mes ROWS UNBOUNDED PRECEDING) AS acumulado
FROM vw_ventas_mensuales_sala ORDER BY id_sala,mes;

-- S12. Todos los vinos de una bodega y, por separado, nunca compraron tintos.
-- Si el universo de vinos está vacío, todos los clientes cumplen la división.
\echo S12_A
SELECT cl.id_cliente,cl.nombre FROM cliente cl WHERE NOT EXISTS (
 SELECT 1 FROM vino v WHERE v.cuit_bodega=:'bodega' AND NOT EXISTS (
  SELECT 1 FROM comprobante c JOIN comprobante_vino cv USING(numero_comprobante)
  WHERE c.id_cliente=cl.id_cliente AND cv.codigo_vino=v.codigo_vino
 )
) ORDER BY cl.id_cliente;
\echo S12_B
SELECT cl.id_cliente,cl.nombre FROM cliente cl WHERE NOT EXISTS (
 SELECT 1 FROM comprobante c JOIN comprobante_vino cv USING(numero_comprobante)
 JOIN vino v USING(codigo_vino) WHERE c.id_cliente=cl.id_cliente AND v.tipo='tinto'
) ORDER BY cl.id_cliente;
