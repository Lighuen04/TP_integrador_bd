SET search_path TO bodegas_atuel, public;

-- Índices de FK que no quedan cubiertas por el prefijo izquierdo de una PK/UNIQUE.
CREATE INDEX IF NOT EXISTS ix_sala_venta_codigo_postal
  ON sala_venta (codigo_postal);
CREATE INDEX IF NOT EXISTS ix_empleado_id_sala
  ON empleado (id_sala);
CREATE INDEX IF NOT EXISTS ix_finca_codigo_postal
  ON finca (codigo_postal);
CREATE INDEX IF NOT EXISTS ix_parcela_id_cepa
  ON parcela (id_cepa);
CREATE INDEX IF NOT EXISTS ix_lote_bodega_destino
  ON lote_uva (cuit_bodega_destino);
CREATE INDEX IF NOT EXISTS ix_analisis_numero_lote_fecha
  ON analisis_calidad (numero_lote, fecha);
CREATE INDEX IF NOT EXISTS ix_vino_cuit_bodega
  ON vino (cuit_bodega);
CREATE INDEX IF NOT EXISTS ix_composicion_id_cepa
  ON composicion_vino_cepa (id_cepa);
CREATE INDEX IF NOT EXISTS ix_vino_maridaje_id_maridaje
  ON vino_maridaje (id_maridaje);
CREATE INDEX IF NOT EXISTS ix_cliente_codigo_postal
  ON cliente (codigo_postal);
CREATE INDEX IF NOT EXISTS ix_permiso_id_exportador
  ON permiso_exportacion (id_exportador);
CREATE INDEX IF NOT EXISTS ix_comprobante_cliente_fecha
  ON comprobante (id_cliente, fecha);
-- S3: igualdad de sala antes del rango de fechas; id_cliente permite leer
-- compradores desde el índice. Sustituye el índice anterior del mismo prefijo.
DROP INDEX IF EXISTS ix_comprobante_sala_fecha;
CREATE INDEX IF NOT EXISTS ix_comprobante_sala_fecha_cubriente
  ON comprobante (id_sala, fecha) INCLUDE (id_cliente);
CREATE INDEX IF NOT EXISTS ix_comprobante_fecha
  ON comprobante (fecha);
-- S2: buscar por vino y recorrer comprobantes ordenados sin leer el detalle.
-- La PK tiene el orden inverso. El índice simple anterior queda cubierto.
DROP INDEX IF EXISTS ix_comprobante_vino_codigo_vino;
CREATE INDEX IF NOT EXISTS ix_comprobante_vino_venta
  ON comprobante_vino (codigo_vino, numero_comprobante);
CREATE INDEX IF NOT EXISTS ix_transportista_localidad_codigo_postal
  ON transportista_localidad (codigo_postal);
CREATE INDEX IF NOT EXISTS ix_ingreso_transportista_fecha
  ON ingreso (codigo_transporte, fecha);
CREATE INDEX IF NOT EXISTS ix_ingreso_bodega
  ON ingreso (cuit_bodega);
CREATE INDEX IF NOT EXISTS ix_ingreso_vino_codigo_vino
  ON ingreso_vino (codigo_vino);
CREATE INDEX IF NOT EXISTS ix_transferencia_sala_fecha
  ON transferencia (id_sala, fecha_confeccion);
-- S5: mismo predicado de pendientes; satisface la variante parcial del TPI.
-- Con solo 18 cabeceras el planificador prefiere Seq Scan: no se atribuye una
-- mejora temporal a este índice; su alcance y costo se miden en el informe.
CREATE INDEX IF NOT EXISTS ix_transferencia_pendientes
  ON transferencia (id_sala) WHERE estado <> 'procesado';
CREATE INDEX IF NOT EXISTS ix_transferencia_vino_codigo_vino
  ON transferencia_vino (codigo_vino);
CREATE INDEX IF NOT EXISTS ix_stock_sala_codigo_vino
  ON stock_sala (codigo_vino);
CREATE INDEX IF NOT EXISTS ix_auditoria_vino_fecha
  ON auditoria_precios (codigo_vino, fecha_del_cambio DESC, hora_del_cambio DESC);
