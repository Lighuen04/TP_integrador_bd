SET search_path TO bodegas_atuel, public;

CREATE TABLE IF NOT EXISTS localidad (
  codigo_postal varchar(16) PRIMARY KEY,
  nombre varchar(120) NOT NULL,
  provincia varchar(120) NOT NULL,
  encargado_regional varchar(160) NOT NULL
);

CREATE TABLE IF NOT EXISTS sala_venta (
  id_sala integer PRIMARY KEY,
  calle varchar(160) NOT NULL,
  numero varchar(20) NOT NULL,
  cierre_semanal varchar(16) NOT NULL,
  codigo_postal varchar(16) NOT NULL,
  CONSTRAINT fk_sala_localidad FOREIGN KEY (codigo_postal)
    REFERENCES localidad (codigo_postal) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS empleado (
  cuit dominio_cuit PRIMARY KEY,
  nombre varchar(160) NOT NULL,
  fecha_laboral date NOT NULL,
  salario numeric(12,2) NOT NULL CHECK (salario > 0),
  id_sala integer NOT NULL,
  CONSTRAINT fk_empleado_sala FOREIGN KEY (id_sala)
    REFERENCES sala_venta (id_sala) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS finca (
  id_finca integer PRIMARY KEY,
  nombre varchar(160) NOT NULL,
  superficie_total numeric(12,3) NOT NULL CHECK (superficie_total > 0),
  departamento varchar(120) NOT NULL,
  codigo_postal varchar(16) NOT NULL,
  CONSTRAINT fk_finca_localidad FOREIGN KEY (codigo_postal)
    REFERENCES localidad (codigo_postal) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS cepa (
  id_cepa integer PRIMARY KEY,
  nombre varchar(120) NOT NULL,
  tipo varchar(16) NOT NULL CHECK (tipo IN ('tinta', 'blanca'))
);

CREATE TABLE IF NOT EXISTS parcela (
  id_finca integer NOT NULL,
  numero_parcela integer NOT NULL CHECK (numero_parcela > 0),
  superficie_total numeric(12,3) NOT NULL CHECK (superficie_total > 0),
  anio_plantacion smallint NOT NULL CHECK (anio_plantacion > 0),
  id_cepa integer NOT NULL,
  CONSTRAINT pk_parcela PRIMARY KEY (id_finca, numero_parcela),
  CONSTRAINT fk_parcela_finca FOREIGN KEY (id_finca)
    REFERENCES finca (id_finca) ON DELETE CASCADE ON UPDATE RESTRICT,
  CONSTRAINT fk_parcela_cepa FOREIGN KEY (id_cepa)
    REFERENCES cepa (id_cepa) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS bodega (
  cuit dominio_cuit PRIMARY KEY,
  razon_social varchar(180) NOT NULL,
  domicilio varchar(240) NOT NULL
);

CREATE TABLE IF NOT EXISTS lote_uva (
  numero_lote integer PRIMARY KEY,
  id_finca integer NOT NULL,
  numero_parcela integer NOT NULL,
  campania smallint NOT NULL CHECK (campania > 0),
  fecha_cosecha date NOT NULL,
  kilos_cosechados numeric(12,3) NOT NULL CHECK (kilos_cosechados > 0),
  cuit_bodega_destino dominio_cuit NOT NULL,
  CONSTRAINT uq_lote_parcela_campania
    UNIQUE (id_finca, numero_parcela, campania),
  CONSTRAINT fk_lote_parcela FOREIGN KEY (id_finca, numero_parcela)
    REFERENCES parcela (id_finca, numero_parcela) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_lote_bodega FOREIGN KEY (cuit_bodega_destino)
    REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS analisis_calidad (
  id_analisis integer PRIMARY KEY,
  numero_lote integer NOT NULL,
  fecha date NOT NULL,
  grado_brix numeric(5,2) NOT NULL,
  ph numeric(5,2) NOT NULL,
  acidez_total numeric(8,3) NOT NULL,
  CONSTRAINT fk_analisis_lote FOREIGN KEY (numero_lote)
    REFERENCES lote_uva (numero_lote) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS vino (
  codigo_vino varchar(40) PRIMARY KEY,
  nombre_comercial varchar(160) NOT NULL,
  tipo varchar(24) NOT NULL,
  anada smallint NOT NULL,
  presentacion_ml integer NOT NULL CHECK (presentacion_ml > 0),
  graduacion_alcoholica numeric(4,2) NOT NULL
    CHECK (graduacion_alcoholica BETWEEN 5 AND 20),
  precio numeric(12,2) NOT NULL CHECK (precio > 0),
  cuit_bodega dominio_cuit NOT NULL,
  CONSTRAINT uq_vino_nombre_anada_presentacion
    UNIQUE (nombre_comercial, anada, presentacion_ml),
  CONSTRAINT fk_vino_bodega FOREIGN KEY (cuit_bodega)
    REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS composicion_vino_cepa (
  codigo_vino varchar(40) NOT NULL,
  id_cepa integer NOT NULL,
  porcentaje_corte numeric(5,2) NOT NULL
    CHECK (porcentaje_corte > 0 AND porcentaje_corte <= 100),
  CONSTRAINT pk_composicion_vino_cepa PRIMARY KEY (codigo_vino, id_cepa),
  CONSTRAINT fk_composicion_vino FOREIGN KEY (codigo_vino)
    REFERENCES vino (codigo_vino) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_composicion_cepa FOREIGN KEY (id_cepa)
    REFERENCES cepa (id_cepa) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS maridaje (
  id_maridaje integer PRIMARY KEY,
  nombre varchar(120) NOT NULL,
  temperatura_servicio numeric(4,1) NOT NULL
);

CREATE TABLE IF NOT EXISTS vino_maridaje (
  codigo_vino varchar(40) NOT NULL,
  id_maridaje integer NOT NULL,
  CONSTRAINT pk_vino_maridaje PRIMARY KEY (codigo_vino, id_maridaje),
  CONSTRAINT fk_vino_maridaje_vino FOREIGN KEY (codigo_vino)
    REFERENCES vino (codigo_vino) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_vino_maridaje_maridaje FOREIGN KEY (id_maridaje)
    REFERENCES maridaje (id_maridaje) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS cliente (
  id_cliente integer PRIMARY KEY,
  apellido varchar(120),
  nombre varchar(160),
  tipo_cliente tipo_cliente NOT NULL,
  tipo_documento varchar(32) NOT NULL,
  numero_documento varchar(40) NOT NULL,
  direccion varchar(240) NOT NULL,
  codigo_postal varchar(16) NOT NULL,
  descuento numeric(5,2) NOT NULL CHECK (descuento BETWEEN 0 AND 100),
  fecha_de_alta date NOT NULL DEFAULT CURRENT_DATE,
  -- Nombre personal o razón social; una empresa no necesita apellido.
  CONSTRAINT ck_cliente_nombre CHECK (COALESCE(btrim(nombre), '') <> ''),
  CONSTRAINT uq_cliente_documento UNIQUE (tipo_documento, numero_documento),
  CONSTRAINT fk_cliente_localidad FOREIGN KEY (codigo_postal)
    REFERENCES localidad (codigo_postal) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS socio (
  id_cliente integer PRIMARY KEY,
  CONSTRAINT fk_socio_cliente FOREIGN KEY (id_cliente)
    REFERENCES cliente (id_cliente) ON DELETE CASCADE ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS distribuidor (
  id_cliente integer PRIMARY KEY,
  zona_cobertura varchar(160) NOT NULL,
  numero_habilitacion varchar(64) NOT NULL,
  CONSTRAINT fk_distribuidor_cliente FOREIGN KEY (id_cliente)
    REFERENCES cliente (id_cliente) ON DELETE CASCADE ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS exportador (
  id_cliente integer PRIMARY KEY,
  pais_destino varchar(120) NOT NULL,
  CONSTRAINT fk_exportador_cliente FOREIGN KEY (id_cliente)
    REFERENCES cliente (id_cliente) ON DELETE CASCADE ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS permiso_exportacion (
  codigo_permiso varchar(40) PRIMARY KEY,
  id_exportador integer NOT NULL,
  fecha_emision date NOT NULL,
  fecha_vencimiento date NOT NULL,
  CONSTRAINT ck_permiso_fechas CHECK (fecha_vencimiento > fecha_emision),
  CONSTRAINT fk_permiso_exportador FOREIGN KEY (id_exportador)
    REFERENCES exportador (id_cliente) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS comprobante (
  numero_comprobante varchar(40) PRIMARY KEY,
  fecha date NOT NULL,
  id_cliente integer NOT NULL,
  id_sala integer NOT NULL,
  descuento_aplicado numeric(5,2) NOT NULL CHECK (descuento_aplicado BETWEEN 0 AND 100),
  total numeric(12,2) NOT NULL DEFAULT 0,
  CONSTRAINT fk_comprobante_cliente FOREIGN KEY (id_cliente)
    REFERENCES cliente (id_cliente) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_comprobante_sala FOREIGN KEY (id_sala)
    REFERENCES sala_venta (id_sala) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS comprobante_vino (
  numero_comprobante varchar(40) NOT NULL,
  codigo_vino varchar(40) NOT NULL,
  cantidad integer NOT NULL CHECK (cantidad > 0),
  precio numeric(12,2) NOT NULL CHECK (precio > 0),
  CONSTRAINT pk_comprobante_vino PRIMARY KEY (numero_comprobante, codigo_vino),
  CONSTRAINT fk_comprobante_vino_comprobante FOREIGN KEY (numero_comprobante)
    REFERENCES comprobante (numero_comprobante) ON DELETE CASCADE ON UPDATE RESTRICT,
  CONSTRAINT fk_comprobante_vino_vino FOREIGN KEY (codigo_vino)
    REFERENCES vino (codigo_vino) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS transportista (
  codigo_transporte varchar(40) PRIMARY KEY,
  razon_social varchar(180) NOT NULL,
  cuit dominio_cuit NOT NULL,
  email varchar(254) NOT NULL,
  telefono varchar(40) NOT NULL,
  domicilio varchar(240) NOT NULL,
  CONSTRAINT uq_transportista_cuit UNIQUE (cuit)
);

CREATE TABLE IF NOT EXISTS transportista_localidad (
  codigo_transporte varchar(40) NOT NULL,
  codigo_postal varchar(16) NOT NULL,
  CONSTRAINT pk_transportista_localidad PRIMARY KEY (codigo_transporte, codigo_postal),
  CONSTRAINT fk_cobertura_transportista FOREIGN KEY (codigo_transporte)
    REFERENCES transportista (codigo_transporte) ON DELETE CASCADE ON UPDATE RESTRICT,
  CONSTRAINT fk_cobertura_localidad FOREIGN KEY (codigo_postal)
    REFERENCES localidad (codigo_postal) ON DELETE CASCADE ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS ingreso (
  codigo_ingreso varchar(40) PRIMARY KEY,
  fecha date NOT NULL,
  estado estado_documento NOT NULL DEFAULT 'en_confeccion',
  codigo_transporte varchar(40) NOT NULL,
  cuit_bodega dominio_cuit NOT NULL,
  CONSTRAINT fk_ingreso_transportista FOREIGN KEY (codigo_transporte)
    REFERENCES transportista (codigo_transporte) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_ingreso_bodega FOREIGN KEY (cuit_bodega)
    REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS ingreso_vino (
  codigo_ingreso varchar(40) NOT NULL,
  codigo_vino varchar(40) NOT NULL,
  cantidad_botellas integer NOT NULL CHECK (cantidad_botellas > 0),
  CONSTRAINT pk_ingreso_vino PRIMARY KEY (codigo_ingreso, codigo_vino),
  CONSTRAINT fk_ingreso_vino_ingreso FOREIGN KEY (codigo_ingreso)
    REFERENCES ingreso (codigo_ingreso) ON DELETE CASCADE ON UPDATE RESTRICT,
  CONSTRAINT fk_ingreso_vino_vino FOREIGN KEY (codigo_vino)
    REFERENCES vino (codigo_vino) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS transferencia (
  numero_solicitud varchar(40) PRIMARY KEY,
  id_sala integer NOT NULL,
  fecha_confeccion date NOT NULL DEFAULT CURRENT_DATE,
  estado estado_documento NOT NULL DEFAULT 'en_confeccion',
  CONSTRAINT fk_transferencia_sala FOREIGN KEY (id_sala)
    REFERENCES sala_venta (id_sala) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS transferencia_vino (
  numero_solicitud varchar(40) NOT NULL,
  codigo_vino varchar(40) NOT NULL,
  cantidad_botellas integer NOT NULL CHECK (cantidad_botellas > 0),
  CONSTRAINT pk_transferencia_vino PRIMARY KEY (numero_solicitud, codigo_vino),
  CONSTRAINT fk_transferencia_vino_transferencia FOREIGN KEY (numero_solicitud)
    REFERENCES transferencia (numero_solicitud) ON DELETE CASCADE ON UPDATE RESTRICT,
  CONSTRAINT fk_transferencia_vino_vino FOREIGN KEY (codigo_vino)
    REFERENCES vino (codigo_vino) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS stock_sala (
  id_sala integer NOT NULL,
  codigo_vino varchar(40) NOT NULL,
  cantidad_stock integer NOT NULL CHECK (cantidad_stock >= 0),
  CONSTRAINT pk_stock_sala PRIMARY KEY (id_sala, codigo_vino),
  CONSTRAINT fk_stock_sala_sala FOREIGN KEY (id_sala)
    REFERENCES sala_venta (id_sala) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_stock_sala_vino FOREIGN KEY (codigo_vino)
    REFERENCES vino (codigo_vino) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS stock_deposito (
  codigo_vino varchar(40) PRIMARY KEY,
  cantidad_botellas_disponibles integer NOT NULL CHECK (cantidad_botellas_disponibles >= 0),
  CONSTRAINT fk_stock_deposito_vino FOREIGN KEY (codigo_vino)
    REFERENCES vino (codigo_vino) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS auditoria_precios (
  id_auditoria bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  codigo_vino varchar(40) NOT NULL,
  precio_anterior numeric(12,2) NOT NULL,
  precio_nuevo numeric(12,2) NOT NULL,
  fecha_del_cambio date NOT NULL,
  hora_del_cambio time NOT NULL,
  usuario_modificacion varchar(160) NOT NULL,
  CONSTRAINT fk_auditoria_vino FOREIGN KEY (codigo_vino)
    REFERENCES vino (codigo_vino) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT ck_auditoria_precios_distintos CHECK (precio_anterior <> precio_nuevo)
);
