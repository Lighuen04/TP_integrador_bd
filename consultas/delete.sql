-- Fase B.2: únicamente D1 y D5. D2/D3/D4/D6 quedan para la etapa 5.
\set ON_ERROR_STOP on
\set sala 2
\set localidad '5620'
SET search_path TO bodegas_atuel, public;

\echo D1
-- D1. Borrar comprobantes de más de cinco años de clientes socios del club.
-- La cabecera elegible elimina detalles por FK CASCADE, sin reintegrar stock.
-- Los controles muestran filas reales; ROLLBACK conserva el dataset de prueba.
BEGIN;
SELECT count(*) AS comprobantes_d1_antes
FROM bodegas_atuel.comprobante c JOIN bodegas_atuel.socio s USING (id_cliente)
WHERE c.fecha < CURRENT_DATE - INTERVAL '5 years';
DELETE FROM bodegas_atuel.comprobante c
USING bodegas_atuel.socio s
WHERE s.id_cliente = c.id_cliente
  AND c.fecha < CURRENT_DATE - INTERVAL '5 years'
RETURNING c.numero_comprobante;
SELECT count(*) AS comprobantes_d1_despues
FROM bodegas_atuel.comprobante c JOIN bodegas_atuel.socio s USING (id_cliente)
WHERE c.fecha < CURRENT_DATE - INTERVAL '5 years';
ROLLBACK;

-- D2. Eliminar cepas sin composición de vinos ni parcelas plantadas.
\echo D2
BEGIN;
SELECT count(*) AS cepas_antes FROM cepa;
DELETE FROM cepa c
WHERE NOT EXISTS(SELECT 1 FROM composicion_vino_cepa vc WHERE vc.id_cepa=c.id_cepa)
  AND NOT EXISTS(SELECT 1 FROM parcela p WHERE p.id_cepa=c.id_cepa)
RETURNING c.id_cepa,c.nombre;
SELECT count(*) AS cepas_despues FROM cepa;
ROLLBACK;

-- D3. Empleados de la sala dada de General Alvear con menos de dos años.
-- No elimina la sala ni empleados de otras salas de esa localidad.
\echo D3
BEGIN;
SELECT e.cuit,e.fecha_laboral FROM empleado e JOIN sala_venta s USING(id_sala)
WHERE e.id_sala=:sala AND s.codigo_postal=:'localidad' ORDER BY e.cuit;
DELETE FROM empleado e USING sala_venta s
WHERE e.id_sala=s.id_sala AND s.id_sala=:sala AND s.codigo_postal=:'localidad'
  AND e.fecha_laboral>CURRENT_DATE-INTERVAL '2 years' RETURNING e.cuit;
SELECT e.cuit,e.fecha_laboral FROM empleado e JOIN sala_venta s USING(id_sala)
WHERE e.id_sala=:sala AND s.codigo_postal=:'localidad' ORDER BY e.cuit;
ROLLBACK;

-- D4. Socios sin compras y alta de más de cinco años; CASCADE quita el subtipo.
\echo D4
BEGIN;
SELECT count(*) AS socios_antes FROM socio;
DELETE FROM cliente c USING socio s
WHERE c.id_cliente=s.id_cliente AND c.fecha_de_alta<CURRENT_DATE-INTERVAL '5 years'
 AND NOT EXISTS(SELECT 1 FROM comprobante cp WHERE cp.id_cliente=c.id_cliente)
RETURNING c.id_cliente;
SELECT count(*) AS socios_despues FROM socio;
ROLLBACK;

\echo D5
-- D5. Eliminar ingresos procesados de más de 365 días.
-- La cascada elimina los renglones; los triggers de stock no actúan en DELETE.
BEGIN;
SELECT count(*) AS ingresos_d5_antes FROM bodegas_atuel.ingreso
WHERE estado = 'procesado' AND fecha < CURRENT_DATE - 365;
DELETE FROM bodegas_atuel.ingreso
WHERE estado = 'procesado' AND fecha < CURRENT_DATE - 365
RETURNING codigo_ingreso;
SELECT count(*) AS ingresos_d5_despues FROM bodegas_atuel.ingreso
WHERE estado = 'procesado' AND fecha < CURRENT_DATE - 365;
ROLLBACK;

-- D6. Socios sin compras de General Alvear, conservando los otros tipos.
\echo D6
BEGIN;
SELECT count(*) AS socios_localidad_antes FROM cliente c JOIN socio s USING(id_cliente)
WHERE c.codigo_postal=:'localidad';
DELETE FROM cliente c USING socio s
WHERE c.id_cliente=s.id_cliente AND c.codigo_postal=:'localidad'
 AND NOT EXISTS(SELECT 1 FROM comprobante cp WHERE cp.id_cliente=c.id_cliente)
RETURNING c.id_cliente;
SELECT count(*) AS socios_localidad_despues FROM cliente c JOIN socio s USING(id_cliente)
WHERE c.codigo_postal=:'localidad';
ROLLBACK;
