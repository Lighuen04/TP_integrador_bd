"""Deriva tipos, nulabilidad, claves, defaults y restricciones del catálogo real."""
import argparse
import json
from pathlib import Path

from operar_docker import Docker

TABLES = {
    'localidad':'Localidades, provincia y encargado regional.',
    'sala_venta':'Salas de venta y localidad de ubicación.',
    'empleado':'Personal asignado obligatoriamente a una sala.',
    'finca':'Fincas productoras y su superficie.',
    'cepa':'Catálogo de variedades de uva.',
    'parcela':'Parcelas de cada finca y cepa plantada.',
    'bodega':'Bodegas elaboradoras identificadas por CUIT.',
    'lote_uva':'Cosecha de una parcela/campaña y bodega de destino.',
    'analisis_calidad':'Mediciones de calidad de un lote de uva.',
    'vino':'Etiqueta, añada, presentación, precio actual y elaborador.',
    'composicion_vino_cepa':'Corte del vino por cepa; suma diferida exactamente 100 %.',
    'maridaje':'Maridajes sugeridos y temperatura de servicio.',
    'vino_maridaje':'Asociación de vinos con maridajes.',
    'cliente':'Supertipo de la especialización total y disjunta.',
    'socio':'Subtipo Socio, con clave compartida con Cliente.',
    'distribuidor':'Subtipo Distribuidor y datos de habilitación/cobertura.',
    'exportador':'Subtipo Exportador y país de destino.',
    'permiso_exportacion':'Permisos de un exportador y su vigencia.',
    'comprobante':'Venta con descuento histórico y total materializado por triggers.',
    'comprobante_vino':'Renglones de venta con cantidad y precio histórico.',
    'transportista':'Empresas de transporte y contacto.',
    'transportista_localidad':'Cobertura de localidades por transportista.',
    'ingreso':'Documento de ingreso desde una bodega al depósito.',
    'ingreso_vino':'Cantidades ingresadas por vino/documento.',
    'transferencia':'Solicitud de transferencia de depósito a sala.',
    'transferencia_vino':'Cantidades solicitadas por vino/transferencia.',
    'stock_sala':'Saldo actual por sala y vino.',
    'stock_deposito':'Saldo actual del depósito por vino.',
    'auditoria_precios':'Historial de cambios efectivos de precio, identificado por sesión PostgreSQL.',
}
DESCRIPTIONS = {
    'codigo_postal':'Identificador de la localidad.', 'nombre':'Nombre o razón social según la entidad.',
    'provincia':'Provincia de la localidad.', 'encargado_regional':'Responsable regional de la localidad.',
    'id_sala':'Identificador de la sala de venta.', 'calle':'Calle del domicilio.', 'numero':'Número del domicilio.',
    'cierre_semanal':'Día de cierre semanal de la sala.', 'cuit':'CUIT de once dígitos.',
    'fecha_laboral':'Fecha de inicio de la relación laboral.', 'salario':'Salario registrado.',
    'id_finca':'Identificador de la finca.', 'superficie_total':'Superficie en hectáreas.',
    'departamento':'Departamento donde se ubica la finca.', 'id_cepa':'Identificador de la cepa.',
    'tipo':'Clasificación de la cepa o del vino según la tabla.',
    'numero_parcela':'Número de parcela dentro de la finca.', 'anio_plantacion':'Año de plantación de la parcela.',
    'razon_social':'Denominación de la empresa.', 'domicilio':'Domicilio de la empresa.',
    'numero_lote':'Identificador del lote cosechado.', 'campania':'Año de la campaña de cosecha.',
    'fecha_cosecha':'Fecha de cosecha del lote.', 'kilos_cosechados':'Kilogramos obtenidos del lote.',
    'cuit_bodega_destino':'CUIT de la bodega que recibe el lote.', 'id_analisis':'Identificador del análisis.',
    'fecha':'Fecha del análisis, ingreso o venta, según la tabla.', 'grado_brix':'Medición de grados Brix.',
    'ph':'Medición de pH.', 'acidez_total':'Medición de acidez total.', 'codigo_vino':'Código único de la etiqueta de vino.',
    'nombre_comercial':'Nombre comercial de la etiqueta.', 'anada':'Año de la añada.',
    'presentacion_ml':'Volumen de la presentación en mililitros.', 'graduacion_alcoholica':'Graduación alcohólica porcentual.',
    'precio':'Precio vigente del vino; en comprobante_vino, precio histórico capturado al vender.',
    'cuit_bodega':'CUIT de la bodega elaboradora.', 'porcentaje_corte':'Participación porcentual de la cepa en el corte.',
    'id_maridaje':'Identificador del maridaje.', 'temperatura_servicio':'Temperatura sugerida en grados Celsius.',
    'id_cliente':'Identificador del cliente; compartido por los subtipos.', 'apellido':'Apellido personal, opcional para empresas.',
    'tipo_cliente':'Discriminante del subtipo: socio, distribuidor o exportador.', 'tipo_documento':'Tipo de documento identificatorio.',
    'numero_documento':'Número de documento; único junto al tipo.', 'direccion':'Dirección del cliente.',
    'descuento':'Descuento vigente; inicializado y validado por trigger según el tipo.',
    'fecha_de_alta':'Fecha de alta del cliente.', 'zona_cobertura':'Zona comercial del distribuidor.',
    'numero_habilitacion':'Habilitación del distribuidor.', 'pais_destino':'País de destino del exportador.',
    'codigo_permiso':'Identificador del permiso.', 'id_exportador':'Cliente del subtipo Exportador titular del permiso.',
    'fecha_emision':'Fecha de emisión del permiso.', 'fecha_vencimiento':'Vencimiento, posterior a su emisión.',
    'numero_comprobante':'Identificador de la venta.', 'descuento_aplicado':'Porcentaje histórico capturado al emitir; inmutable.',
    'total':'Total neto materializado a partir de renglones y descuento histórico; no es entrada libre.',
    'cantidad':'Número de botellas vendidas.', 'codigo_transporte':'Identificador del transportista.',
    'email':'Correo de contacto.', 'telefono':'Teléfono de contacto.', 'codigo_ingreso':'Identificador del ingreso.',
    'estado':'Estado documental: en_confeccion → terminado → procesado.',
    'cantidad_botellas':'Cantidad de botellas del renglón.', 'numero_solicitud':'Identificador de la transferencia.',
    'fecha_confeccion':'Fecha de confección fijada por PostgreSQL al crear la transferencia.',
    'cantidad_stock':'Saldo actual de botellas en la sala, no negativo.',
    'cantidad_botellas_disponibles':'Saldo actual de botellas en depósito, no negativo.',
    'id_auditoria':'Identificador identity de la auditoría.', 'precio_anterior':'Precio vigente antes del cambio.',
    'precio_nuevo':'Precio vigente después del cambio.', 'fecha_del_cambio':'Fecha real del cambio de precio.',
    'hora_del_cambio':'Hora real del cambio de precio.', 'usuario_modificacion':'session_user autenticado que originó el cambio.',
}

QUERY = """SET search_path=bodegas_atuel,pg_catalog;
SELECT json_agg(json_build_object('tabla',c.relname,'columnas',(
  SELECT json_agg(json_build_object('nombre',a.attname,'tipo',format_type(a.atttypid,a.atttypmod),
    'no_nulo',a.attnotnull,'identity',a.attidentity,'default',pg_get_expr(d.adbin,d.adrelid),
    'pk',EXISTS(SELECT 1 FROM pg_constraint k WHERE k.conrelid=c.oid AND k.contype='p' AND a.attnum=ANY(k.conkey)),
    'fk',EXISTS(SELECT 1 FROM pg_constraint k WHERE k.conrelid=c.oid AND k.contype='f' AND a.attnum=ANY(k.conkey))) ORDER BY a.attnum)
  FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
  WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'restricciones',(SELECT json_agg(json_build_object('nombre',k.conname,'definicion',pg_get_constraintdef(k.oid,true)) ORDER BY k.conname)
   FROM pg_constraint k WHERE k.conrelid=c.oid AND k.contype IN ('p','f','u','c')),
 'triggers',(SELECT json_agg(pg_get_triggerdef(t.oid,true) ORDER BY t.tgname)
   FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal)) ORDER BY c.relname)
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='bodegas_atuel' AND c.relkind='r';"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base')
    parser.add_argument('--salida',type=Path,default=Path('docs/diccionario_datos.md'))
    args = parser.parse_args()
    docker = Docker()
    tables = json.loads(docker.psql(args.base or docker.base,QUERY))
    assert len(tables) == 29
    lines = ['# Diccionario de datos — esquema físico', '',
        'Derivado del catálogo PostgreSQL real mediante `scripts/generar_diccionario.py`.',
        'Tipos, nulabilidad, defaults, PK/FK, restricciones y triggers se extraen sin modificar la base.',
        'Las descripciones explican los nombres existentes; no agregan atributos ni reglas.', '',
        'Los tamaños numeric indican precisión y escala. PK/FK compuestas y acciones referenciales se detallan debajo de cada tabla.',
        'Un campo NOT NULL sin DEFAULT SQL puede ser completado por un BEFORE trigger (por ejemplo descuentos).', '',
        'Tipos propios: `estado_documento` = en_confeccion/terminado/procesado; `tipo_cliente` = socio/distribuidor/exportador;',
        '`dominio_cuit` = varchar(11), CHECK de once dígitos. Su definición ejecutable está en `database/01_tipos_dominios.sql`.', '']
    for t in tables:
        lines += [f"## {t['tabla']}", '', TABLES[t['tabla']], '',
                  '| Columna | Tipo PostgreSQL | Nulo | Clave | Default / identity | Descripción |',
                  '|---|---|---|---|---|---|']
        for c in t['columnas']:
            description = DESCRIPTIONS[c['nombre']]
            key = '/'.join(k for k in ('PK','FK') if c[k.lower()]) or '—'
            default = c['default'] or ('GENERATED BY DEFAULT AS IDENTITY' if c['identity']=='d' else '—')
            lines.append(f"| `{c['nombre']}` | `{c['tipo']}` | {'No' if c['no_nulo'] else 'Sí'} | {key} | `{default}` | {description} |")
        lines += ['', 'Restricciones del catálogo:', '']
        lines += [f"- `{r['nombre']}`: `{r['definicion']}`." for r in t['restricciones'] or []]
        if t['triggers']:
            lines += ['', 'Triggers (incluidas validaciones diferidas):', '']
            lines += [f'- `{definition}`.' for definition in t['triggers']]
        lines += ['']
    args.salida.write_text('\n'.join(lines),encoding='utf-8')
    print(json.dumps({'tablas':len(tables),'columnas':sum(len(t['columnas']) for t in tables),'archivo':str(args.salida)}))


if __name__ == '__main__':
    main()
