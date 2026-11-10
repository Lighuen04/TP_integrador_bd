\set ON_ERROR_STOP on
\set bodega '20200000001'
SET search_path TO bodegas_atuel, public;

-- U1. Recalcular todos los comprobantes usando su descuento histórico.
-- «Por tipo de cliente» se interpreta según la decisión aprobada, sin cambiar tasas.
\echo U1
BEGIN;
SELECT count(*) AS comprobantes_antes,sum(total) AS total_antes FROM comprobante;
SELECT fn_recalcular_totales_comprobantes() AS comprobantes_recalculados;
SELECT count(*) AS comprobantes_despues,sum(total) AS total_despues,
       count(*) FILTER(WHERE total<>fn_total_comprobante(numero_comprobante)) AS inconsistentes
FROM comprobante;
ROLLBACK;

-- U2. Aumentar 20 % salarios de empleados con más de cinco años.
-- Filtrar por fecha incluye cinco años y un día; los años enteros no bastan.
\echo U2
BEGIN;
SELECT cuit,salario,fn_antiguedad_anios(fecha_laboral) AS anios_enteros
FROM empleado WHERE fecha_laboral<CURRENT_DATE-INTERVAL '5 years' ORDER BY cuit;
UPDATE empleado SET salario=ROUND(salario*1.20,2)
WHERE fecha_laboral<CURRENT_DATE-INTERVAL '5 years' RETURNING cuit,salario;
SELECT cuit,salario FROM empleado WHERE fecha_laboral<CURRENT_DATE-INTERVAL '5 years' ORDER BY cuit;
ROLLBACK;

-- U3. Incrementar 13 % precios de la bodega; RN-13 audita cambios efectivos.
\echo U3
BEGIN;
SELECT codigo_vino,precio FROM vino WHERE cuit_bodega=:'bodega' ORDER BY codigo_vino;
SELECT count(*) AS auditorias_antes FROM auditoria_precios;
UPDATE vino SET precio=ROUND(precio*1.13,2) WHERE cuit_bodega=:'bodega' RETURNING codigo_vino,precio;
SELECT count(*) AS auditorias_despues FROM auditoria_precios;
SELECT codigo_vino,precio FROM vino WHERE cuit_bodega=:'bodega' ORDER BY codigo_vino;
ROLLBACK;

-- U4. Intercambiar lunes y miércoles mediante una sola sentencia UPDATE.
\echo U4
BEGIN;
SELECT id_sala,cierre_semanal FROM sala_venta ORDER BY id_sala;
UPDATE sala_venta SET cierre_semanal=CASE cierre_semanal WHEN 'lunes' THEN 'miércoles' ELSE 'lunes' END
WHERE cierre_semanal IN ('lunes','miércoles') RETURNING id_sala,cierre_semanal;
SELECT id_sala,cierre_semanal FROM sala_venta ORDER BY id_sala;
ROLLBACK;

-- U5. Reducir 15 % los diez vinos menos vendidos, incluidos los nunca vendidos.
-- Código resuelve empates; el LEFT JOIN conserva vinos con cero ventas.
\echo U5
BEGIN;
SELECT v.codigo_vino,v.precio,COALESCE(sum(cv.cantidad),0) AS botellas
FROM vino v LEFT JOIN comprobante_vino cv USING(codigo_vino)
GROUP BY v.codigo_vino ORDER BY botellas,v.codigo_vino LIMIT 10;
WITH menos_vendidos AS (
 SELECT v.codigo_vino FROM vino v LEFT JOIN comprobante_vino cv USING(codigo_vino)
 GROUP BY v.codigo_vino ORDER BY COALESCE(sum(cv.cantidad),0),v.codigo_vino LIMIT 10
)
UPDATE vino v SET precio=ROUND(v.precio*0.85,2) FROM menos_vendidos m
WHERE v.codigo_vino=m.codigo_vino RETURNING v.codigo_vino,v.precio;
SELECT v.codigo_vino,v.precio,COALESCE(sum(cv.cantidad),0) AS botellas
FROM vino v LEFT JOIN comprobante_vino cv USING(codigo_vino)
GROUP BY v.codigo_vino ORDER BY botellas,v.codigo_vino LIMIT 10;
ROLLBACK;

-- U6. Descuento vigente de 35 % para exportadores con más de tres permisos.
-- No actualiza comprobantes y omite escrituras sin cambio efectivo.
\echo U6
BEGIN;
SELECT descuento,count(*) AS exportadores FROM cliente WHERE tipo_cliente='exportador' GROUP BY descuento ORDER BY descuento;
SELECT sum(total) AS ventas_antes,sum(descuento_aplicado) AS tasas_antes FROM comprobante;
UPDATE cliente SET descuento=35 WHERE tipo_cliente='exportador' AND descuento<>35 AND id_cliente IN (
 SELECT id_exportador FROM permiso_exportacion GROUP BY id_exportador HAVING count(*)>3
) RETURNING id_cliente,descuento;
SELECT descuento,count(*) AS exportadores FROM cliente WHERE tipo_cliente='exportador' GROUP BY descuento ORDER BY descuento;
SELECT sum(total) AS ventas_despues,sum(descuento_aplicado) AS tasas_despues FROM comprobante;
ROLLBACK;
