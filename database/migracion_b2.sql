-- Solo para instalaciones anteriores a B.2. Ejecutar con psql como propietario.
-- CREATE TABLE IF NOT EXISTS no modifica la acción de una FK ya instalada.
\set ON_ERROR_STOP on
BEGIN;
-- Impide exponer una combinación intermedia de FK y triggers a otras sesiones.
LOCK TABLE bodegas_atuel.comprobante, bodegas_atuel.comprobante_vino,
  bodegas_atuel.ingreso, bodegas_atuel.ingreso_vino IN ACCESS EXCLUSIVE MODE;
ALTER TABLE bodegas_atuel.comprobante_vino
  DROP CONSTRAINT fk_comprobante_vino_comprobante,
  ADD CONSTRAINT fk_comprobante_vino_comprobante
    FOREIGN KEY (numero_comprobante)
    REFERENCES bodegas_atuel.comprobante (numero_comprobante)
    ON DELETE CASCADE ON UPDATE RESTRICT;
\ir 05_triggers.sql
COMMIT;
