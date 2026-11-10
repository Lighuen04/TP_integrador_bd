\set ON_ERROR_STOP on
\set localidad '5620'
\set cliente 1
\set comprobante 'TPI-I3'
\set ingreso 'TPI-I6'
\set vino 'V001'
\set transportista 'T1'
SET search_path TO bodegas_atuel, public;

-- I1. Cobertura de General Alvear al transportista de menos ingresos del trimestre.
-- Incluye actividad cero; empate por código descendente (T4 en esta carga).
-- Se elige el mínimo global antes de comprobar cobertura. Si ya existe, la
-- operación es idempotente: no se sustituye por otro de mayor actividad.
\echo I1
BEGIN;
SELECT codigo_transporte FROM transportista_localidad WHERE codigo_postal=:'localidad';
WITH menor_actividad AS (
 SELECT t.codigo_transporte FROM transportista t LEFT JOIN ingreso i
 ON i.codigo_transporte=t.codigo_transporte
 AND i.fecha>=CURRENT_DATE-INTERVAL '3 months' AND i.fecha<CURRENT_DATE+1
 GROUP BY t.codigo_transporte ORDER BY count(i.codigo_ingreso),t.codigo_transporte DESC LIMIT 1
)
INSERT INTO transportista_localidad SELECT codigo_transporte,:'localidad' FROM menor_actividad
ON CONFLICT DO NOTHING RETURNING codigo_transporte,codigo_postal;
SELECT codigo_transporte FROM transportista_localidad WHERE codigo_postal=:'localidad';
ROLLBACK;

-- I2. Si hay tintos >=14°, crear «cordero al disco» y asociarlos sin duplicar.
-- No hay identity ni UNIQUE de nombre. Se reutiliza el menor ID si ya existe;
-- el bloqueo serializa MAX+1 entre estas operaciones.
\echo I2
BEGIN;
LOCK TABLE maridaje IN SHARE ROW EXCLUSIVE MODE;
SELECT count(*) AS asociaciones_antes FROM vino_maridaje vm JOIN maridaje m USING(id_maridaje) WHERE m.nombre='cordero al disco';
INSERT INTO maridaje(id_maridaje,nombre,temperatura_servicio)
SELECT COALESCE(max(id_maridaje),0)+1,'cordero al disco',17 FROM maridaje
HAVING EXISTS(SELECT 1 FROM vino WHERE tipo='tinto' AND graduacion_alcoholica>=14)
AND NOT EXISTS(SELECT 1 FROM maridaje WHERE nombre='cordero al disco') RETURNING id_maridaje,nombre;
INSERT INTO vino_maridaje(codigo_vino,id_maridaje)
SELECT v.codigo_vino,(SELECT min(id_maridaje) FROM maridaje WHERE nombre='cordero al disco')
FROM vino v WHERE v.tipo='tinto' AND v.graduacion_alcoholica>=14
ON CONFLICT DO NOTHING RETURNING codigo_vino,id_maridaje;
SELECT count(*) AS asociaciones_despues FROM vino_maridaje vm JOIN maridaje m USING(id_maridaje) WHERE m.nombre='cordero al disco';
ROLLBACK;

-- I3. Venta de tres vinos al cliente dado en sala 1, en una transacción.
-- La PK varchar requiere un número nuevo; no existe generador de comprobantes.
-- El precio se copia del vino; stock, tasa histórica y total los mantiene la BD.
\echo I3
BEGIN;
SELECT codigo_vino,fn_stock_sala(1,codigo_vino) AS stock_antes,precio FROM vino
WHERE codigo_vino IN ('V001','V002','V003') ORDER BY codigo_vino;
INSERT INTO comprobante(numero_comprobante,fecha,id_cliente,id_sala)
VALUES (:'comprobante',CURRENT_DATE,:cliente,1);
INSERT INTO comprobante_vino(numero_comprobante,codigo_vino,cantidad,precio)
SELECT :'comprobante',sol.codigo_vino,1,v.precio
FROM (VALUES ('V001'),('V002'),('V003')) sol(codigo_vino)
LEFT JOIN vino v ON v.codigo_vino=sol.codigo_vino
ORDER BY sol.codigo_vino RETURNING codigo_vino,cantidad,precio;
-- LEFT JOIN conserva los tres pedidos: si falta un vino, los controles
-- existentes (stock, NOT NULL/FK) rechazan la venta en vez de omitir renglones.
SELECT numero_comprobante,descuento_aplicado,fn_descuento_cliente(id_cliente) AS descuento_vigente,
total,fn_total_comprobante(numero_comprobante) AS total_calculado FROM comprobante WHERE numero_comprobante=:'comprobante';
SELECT codigo_vino,fn_stock_sala(1,codigo_vino) AS stock_despues FROM vino
WHERE codigo_vino IN ('V001','V002','V003') ORDER BY codigo_vino;
ROLLBACK;

-- I4. Insertar una bodega nueva con CUIT ficticio válido para el dominio.
\echo I4
BEGIN;
SELECT count(*) AS bodegas_antes FROM bodega;
INSERT INTO bodega(cuit,razon_social,domicilio)
VALUES ('20999999990','Bodega demostración TPI','Ruta 144 km 20') RETURNING *;
SELECT count(*) AS bodegas_despues FROM bodega;
ROLLBACK;

-- I5. Insertar sala nueva; su ID no tiene identity y se asigna bajo bloqueo.
\echo I5
BEGIN;
LOCK TABLE sala_venta IN SHARE ROW EXCLUSIVE MODE;
SELECT count(*) AS salas_antes FROM sala_venta;
INSERT INTO sala_venta(id_sala,calle,numero,cierre_semanal,codigo_postal)
SELECT COALESCE(max(id_sala),0)+1,'Calle demostración','100','domingo','5600' FROM sala_venta RETURNING *;
SELECT count(*) AS salas_despues FROM sala_venta;
ROLLBACK;

-- I6. Ingreso en confección de 120 botellas de Malbec Reserva 750 ml (V001).
-- Bodega obtenida del vino, transportista T1. No se procesa ni aumenta stock.
\echo I6
BEGIN;
SELECT cantidad_botellas_disponibles AS stock_antes FROM stock_deposito WHERE codigo_vino=:'vino';
INSERT INTO ingreso(codigo_ingreso,fecha,codigo_transporte,cuit_bodega)
SELECT :'ingreso',CURRENT_DATE,:'transportista',cuit_bodega FROM vino WHERE codigo_vino=:'vino';
INSERT INTO ingreso_vino(codigo_ingreso,codigo_vino,cantidad_botellas)
VALUES (:'ingreso',:'vino',120) RETURNING *;
SELECT i.codigo_ingreso,i.estado,iv.cantidad_botellas,d.cantidad_botellas_disponibles AS stock_despues
FROM ingreso i JOIN ingreso_vino iv USING(codigo_ingreso) JOIN stock_deposito d USING(codigo_vino)
WHERE i.codigo_ingreso=:'ingreso';
ROLLBACK;
