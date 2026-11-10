"""Carga de prueba Bodegas del Atuel: una transacción, COPY y reglas de la BD."""
import argparse
import csv
import hashlib
import json
import random
import sys
from collections import Counter
from datetime import date, timedelta
from decimal import Decimal
from itertools import islice
from pathlib import Path
from time import perf_counter

import psycopg
from psycopg import sql
from faker import Faker, VERSION as FAKER_VERSION

BASE = Path(__file__).resolve().parent


def copiar(cur, tabla, columnas, filas):
    consulta = sql.SQL("COPY bodegas_atuel.{} ({}) FROM STDIN").format(
        sql.Identifier(tabla), sql.SQL(',').join(map(sql.Identifier, columnas.split(','))))
    with cur.copy(consulta) as copia:
        for fila in filas:
            copia.write_row(fila)


def catalogo(nombre):
    with (BASE / 'catalogos' / (nombre + '.csv')).open(encoding='utf8', newline='') as archivo:
        return list(csv.DictReader(archivo))


def ventas(seed, referencia, cantidad):
    """Se recorre dos veces: sumar demanda y luego cargar, sin guardar ventas."""
    rng = random.Random(seed)
    for i in range(cantidad):
        antiguo = i < 5000
        fecha = (referencia.replace(year=referencia.year - 6) + timedelta(days=i % 90)
                 if antiguo else referencia - timedelta(days=rng.randrange(90)))
        vinos = [0 if i < 6 else rng.randrange(36)]
        vinos.append((vinos[0] + rng.randrange(1, 36)) % 36)
        yield (f'C{i + 1:06}', fecha, i % 19000 + 1, i % 6 + 1,
               [(f'V{v + 1:03}', rng.randrange(1, 4)) for v in vinos], antiguo)


def cargar(cur, args):
    ref = args.fecha_ref
    fake = Faker('es_AR')
    fake.seed_instance(args.seed)
    localidades = catalogo('localidades')
    departamentos = [r['nombre'] for r in catalogo('departamentos')]
    tipos = [r['tipo'] for r in catalogo('tipos_vino')]
    copiar(cur, 'localidad', 'codigo_postal,nombre,provincia,encargado_regional',
           ((r['codigo_postal'], r['nombre'], r['provincia'], fake.name()) for r in localidades))
    copiar(cur, 'cepa', 'id_cepa,nombre,tipo',
           ((int(r['id_cepa']), r['nombre'], r['tipo']) for r in catalogo('cepas')))
    copiar(cur, 'maridaje', 'id_maridaje,nombre,temperatura_servicio',
           ((int(r['id_maridaje']), r['nombre'], Decimal(r['temperatura_servicio'])) for r in catalogo('maridajes')))
    copiar(cur, 'sala_venta', 'id_sala,calle,numero,cierre_semanal,codigo_postal',
           ((i, f'Calle {i}', str(i * 100), ['lunes', 'miércoles', 'domingo'][i % 3],
             localidades[(i - 1) % 3]['codigo_postal']) for i in range(1, 7)))
    copiar(cur, 'empleado', 'cuit,nombre,fecha_laboral,salario,id_sala',
           ((str(20100000000 + i), fake.name(), ref - timedelta(days=365 * (8 if i % 2 else 1)),
             Decimal('900000.00') + i * 1000, (i - 1) % 6 + 1) for i in range(1, 19)))
    copiar(cur, 'finca', 'id_finca,nombre,superficie_total,departamento,codigo_postal',
           ((i, f'Finca {i}', 40, departamentos[(i - 1) % 3], localidades[(i - 1) % 3]['codigo_postal'])
            for i in range(1, 7)))
    copiar(cur, 'parcela', 'id_finca,numero_parcela,superficie_total,anio_plantacion,id_cepa',
           ((f, p, 5 + p, ref.year - 15, (f + p) % 10 + 1) for f in range(1, 7) for p in range(1, 5)))
    bodegas = [str(20200000000 + i) for i in range(1, 5)]
    copiar(cur, 'bodega', 'cuit,razon_social,domicilio',
           ((b, f'Bodega Atuel {i}', f'Ruta {i} km 10') for i, b in enumerate(bodegas, 1)))
    campania = ref.year if ref >= date(ref.year, 4, 30) else ref.year - 1
    lotes = [(n, f, p, anio, date(anio, 3, 15), Decimal((6 + p) * (700 + f * 50 + p * 130)),
              bodegas[(f - 1) % 4])
             for n, (f, p, anio) in enumerate(((f, p, a) for f in range(1, 7)
                 for p in range(1, 5) for a in range(campania - 4, campania + 1)), 1)]
    copiar(cur, 'lote_uva', 'numero_lote,id_finca,numero_parcela,campania,fecha_cosecha,kilos_cosechados,cuit_bodega_destino', lotes)
    copiar(cur, 'analisis_calidad', 'id_analisis,numero_lote,fecha,grado_brix,ph,acidez_total',
           ((n * 2 - j, n, fecha + timedelta(days=j + 1), Decimal('23.5'), Decimal('3.4'), Decimal('5.2'))
            for n, _, _, _, fecha, _, _ in lotes for j in (0, 1)))
    precios = {f'V{i:03}': Decimal(1000 + i * 50) for i in range(1, 41)}
    copiar(cur, 'vino', 'codigo_vino,nombre_comercial,tipo,anada,presentacion_ml,graduacion_alcoholica,precio,cuit_bodega',
           ((f'V{i:03}', 'Malbec Reserva' if i == 1 else f'Atuel {i}', tipos[(i - 1) % 4],
             ref.year - 9 + i % 3, 750 if i == 1 else [187, 375, 750, 1500, 3000][i % 5],
             Decimal('14.5') if i % 2 else Decimal('12.5'), precios[f'V{i:03}'], bodegas[(i - 1) % 4])
            for i in range(1, 41)))
    composiciones = []
    for i in range(1, 41):
        cepas = list(range(1, 8)) if tipos[(i - 1) % 4] in ('tinto', 'rosado') else [8, 9, 10]
        composiciones.extend((f'V{i:03}', cepas[(i - 1 + j) % len(cepas)], porcentaje)
                             for j, porcentaje in enumerate([100] if i % 2 else [70, 30]))
    copiar(cur, 'composicion_vino_cepa', 'codigo_vino,id_cepa,porcentaje_corte', composiciones)
    copiar(cur, 'vino_maridaje', 'codigo_vino,id_maridaje',
           ((f'V{i:03}', (i - 1) % 8 + 1) for i in range(1, 41)))
    copiar(cur, 'cliente', 'id_cliente,nombre,apellido,tipo_cliente,tipo_documento,numero_documento,direccion,codigo_postal,fecha_de_alta',
           ((i, fake.name() if i % 3 == 1 else fake.company(), None,
             ['exportador', 'socio', 'distribuidor'][i % 3], 'DNI' if i % 3 == 1 else 'CUIT',
             str((30000000 if i % 3 == 1 else 20000000000) + i), fake.street_address(), localidades[i % 3]['codigo_postal'],
             ref.replace(year=ref.year - 8)) for i in range(1, 20001)))
    copiar(cur, 'socio', 'id_cliente', ((i,) for i in range(1, 20001) if i % 3 == 1))
    copiar(cur, 'distribuidor', 'id_cliente,zona_cobertura,numero_habilitacion',
           ((i, departamentos[i % 18], f'H{i}') for i in range(2, 20001, 3)))
    copiar(cur, 'exportador', 'id_cliente,pais_destino', ((i, 'Chile') for i in range(3, 20001, 3)))
    copiar(cur, 'permiso_exportacion', 'codigo_permiso,id_exportador,fecha_emision,fecha_vencimiento',
           ((f'P{i}-{j}', i, ref.replace(year=ref.year - 7), ref.replace(year=ref.year + 2))
            for i in range(3, 20001, 3) for j in range(1, 5 if i % 2 == 0 else 2)))
    copiar(cur, 'transportista', 'codigo_transporte,razon_social,cuit,email,telefono,domicilio',
           ((f'T{i}', f'Transportes {i}', str(20300000000 + i), f't{i}@example.invalid',
             f'260400000{i}', f'Ruta {i}') for i in range(1, 5)))
    copiar(cur, 'transportista_localidad', 'codigo_transporte,codigo_postal',
           ((f'T{i}', r['codigo_postal']) for i in range(1, 5) for r in localidades if not (i == 4 and r['codigo_postal'] == '5620')))
    # Resolver composición e ISA ahora, antes de cargar cientos de miles de ventas.
    cur.execute('SET CONSTRAINTS ALL IMMEDIATE')
    demanda = Counter()
    for _, _, _, sala, lineas, _ in ventas(args.seed, ref, args.comprobantes):
        for vino, cantidad in lineas:
            demanda[sala, vino] += cantidad
    cantidades = {(s, v): n + (0 if (s, v) == (6, 'V036') else 50) for (s, v), n in demanda.items()}
    antigua = ref.replace(year=ref.year - 6) - timedelta(days=1)
    # La única importación histórica especial afecta fecha de cabeceras, no
    # estado/stock. FK y CHECK siguen activos; restaurar antes de todo UPDATE.
    transferencias = [(f'TR-H{s}', s, antigua, 'en_confeccion') for s in range(1, 7)]
    transferencias += [(f'TR-R{s}', s, ref - timedelta(days=10), 'en_confeccion') for s in range(1, 7)]
    transferencias += [(f'TR-P{s}', s, ref - timedelta(days=7), 'en_confeccion') for s in range(1, 7)]
    cur.execute('ALTER TABLE bodegas_atuel.transferencia DISABLE TRIGGER trg_transferencia_estado')
    copiar(cur, 'transferencia', 'numero_solicitud,id_sala,fecha_confeccion,estado', transferencias)
    cur.execute('ALTER TABLE bodegas_atuel.transferencia ENABLE TRIGGER trg_transferencia_estado')
    # Ingresos por bodega, antes del primer traslado y también durante el último mes.
    for reciente in (False, True):
        for i, bodega in enumerate(bodegas, 1):
            codigo = f'IG-{"R" if reciente else "H"}{i}'
            cur.execute('INSERT INTO bodegas_atuel.ingreso (codigo_ingreso,fecha,codigo_transporte,cuit_bodega) VALUES (%s,%s,%s,%s)',
                        (codigo, ref - timedelta(days=20) if reciente else antigua - timedelta(days=1), f'T{i}', bodega))
            filas = [(codigo, f'V{v:03}', 50 if reciente else sum(n for (s, w), n in cantidades.items() if w == f'V{v:03}') + 500)
                     for v in range(i, 41, 4)]
            copiar(cur, 'ingreso_vino', 'codigo_ingreso,codigo_vino,cantidad_botellas', filas)
            cur.execute("UPDATE bodegas_atuel.ingreso SET estado='terminado' WHERE codigo_ingreso=%s", (codigo,))
            cur.execute('CALL bodegas_atuel.sp_procesar_ingreso(%s)', (codigo,))
    copiar(cur, 'transferencia_vino', 'numero_solicitud,codigo_vino,cantidad_botellas',
           ((f'TR-H{s}', v, n) for (s, v), n in sorted(cantidades.items())))
    copiar(cur, 'transferencia_vino', 'numero_solicitud,codigo_vino,cantidad_botellas',
           ((f'TR-{prefijo}{s}', f'V{s:03}', 10) for prefijo in ('R', 'P') for s in range(1, 7)))
    for prefijo in ('H', 'R'):
        for s in range(1, 7):
            codigo = f'TR-{prefijo}{s}'
            cur.execute("UPDATE bodegas_atuel.transferencia SET estado='terminado' WHERE numero_solicitud=%s", (codigo,))
            cur.execute('CALL bodegas_atuel.sp_procesar_transferencia(%s)', (codigo,))
    cur.execute("UPDATE bodegas_atuel.transferencia SET estado='terminado' WHERE numero_solicitud IN ('TR-P2','TR-P4','TR-P6')")
    # Los lotes cortan exactamente en el cambio de descuento/precio histórico.
    flujo = iter(ventas(args.seed, ref, args.comprobantes))
    for inicio in range(0, args.comprobantes, 1000):
        if inicio == 5000:
            cur.execute("UPDATE bodegas_atuel.cliente SET descuento=35 WHERE tipo_cliente='exportador' AND id_cliente % 12=0")
            cur.execute('UPDATE bodegas_atuel.vino SET precio=precio*1.10')
        lote = list(islice(flujo, 1000))
        copiar(cur, 'comprobante', 'numero_comprobante,fecha,id_cliente,id_sala', (v[:4] for v in lote))
        copiar(cur, 'comprobante_vino', 'numero_comprobante,codigo_vino,cantidad,precio',
               ((numero, vino, cantidad, precios[vino] * (1 if antiguo else Decimal('1.10')))
                for numero, _, _, _, lineas, antiguo in lote for vino, cantidad in lineas))
        if inicio % 10000 == 0:
            print(f'Ventas cargadas: {inicio + len(lote)}', file=sys.stderr, flush=True)


def validar(conn, referencia):
    consulta = (BASE / 'validar_carga.sql').read_text(encoding='utf8')
    # Fecha tipada por argparse; no se interpolan entradas SQL libres.
    consulta = consulta.replace(":'fecha_ref'", "'" + referencia.isoformat() + "'")
    resultados = {}
    with conn.cursor() as cur:
        cur.execute(consulta)
        while True:
            if cur.description:
                columnas = [col.name for col in cur.description]
                clave = 'integridad' if columnas[0] == 'control' else 'estados_' + columnas[1]
                resultados[clave] = dict(cur.fetchall())
            if not cur.nextset():
                break
    return resultados


def resumen(conn):
    """Huella por PK en streaming. Solo se excluyen metadatos del reloj de auditoría."""
    tablas = conn.execute("SELECT tablename FROM pg_tables WHERE schemaname='bodegas_atuel' ORDER BY tablename").fetchall()
    resultado = {}
    for (tabla,) in tablas:
        columnas = conn.execute("SELECT attname FROM pg_attribute WHERE attrelid=%s::regclass AND attnum>0 AND NOT attisdropped ORDER BY attnum", ('bodegas_atuel.' + tabla,)).fetchall()
        nombres = [c[0] for c in columnas if tabla != 'auditoria_precios' or c[0] not in ('fecha_del_cambio', 'hora_del_cambio', 'usuario_modificacion')]
        claves = conn.execute("SELECT a.attname FROM pg_index i CROSS JOIN LATERAL unnest(i.indkey) WITH ORDINALITY k(num,orden) JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.num WHERE i.indrelid=%s::regclass AND i.indisprimary ORDER BY k.orden", ('bodegas_atuel.' + tabla,)).fetchall()
        query = sql.SQL('COPY (SELECT {} FROM bodegas_atuel.{} ORDER BY {}) TO STDOUT').format(
            sql.SQL(',').join(map(sql.Identifier, nombres)), sql.Identifier(tabla), sql.SQL(',').join(sql.Identifier(k[0]) for k in claves))
        huella = hashlib.sha256()
        with conn.cursor().copy(query) as copia:
            for bloque in copia:
                huella.update(bloque)
        cantidad = conn.execute(sql.SQL('SELECT count(*) FROM bodegas_atuel.{}').format(sql.Identifier(tabla))).fetchone()[0]
        resultado[tabla] = {'filas': cantidad, 'sha256': huella.hexdigest()}
    return resultado


def benchmark(conn, referencia):
    tiempos = {}
    for modo in ('fila', 'copy'):
        with conn.transaction():
            cur = conn.cursor()
            # Mismo stock de partida con mecanismos normales; el aprovisionamiento
            # y las cabeceras no forman parte del tiempo de inserción de renglones.
            cur.execute("INSERT INTO bodegas_atuel.ingreso (codigo_ingreso,fecha,codigo_transporte,cuit_bodega) VALUES ('BENCH',%s,'T1','20200000001')", (referencia,))
            cur.execute("INSERT INTO bodegas_atuel.ingreso_vino VALUES ('BENCH','V001',2000)")
            cur.execute("UPDATE bodegas_atuel.ingreso SET estado='terminado' WHERE codigo_ingreso='BENCH'")
            cur.execute("CALL bodegas_atuel.sp_procesar_ingreso('BENCH')")
            cur.execute("INSERT INTO bodegas_atuel.transferencia (numero_solicitud,id_sala) VALUES ('BENCH',1)")
            cur.execute("INSERT INTO bodegas_atuel.transferencia_vino VALUES ('BENCH','V001',2000)")
            cur.execute("UPDATE bodegas_atuel.transferencia SET estado='terminado' WHERE numero_solicitud='BENCH'")
            cur.execute("CALL bodegas_atuel.sp_procesar_transferencia('BENCH')")
            copiar(cur, 'comprobante', 'numero_comprobante,fecha,id_cliente,id_sala', ((f'B{i}', referencia, 1, 1) for i in range(2000)))
            filas = [(f'B{i}', 'V001', 1, Decimal('1155')) for i in range(2000)]
            inicio = perf_counter()
            if modo == 'fila':
                for fila in filas:
                    cur.execute('INSERT INTO bodegas_atuel.comprobante_vino VALUES (%s,%s,%s,%s)', fila)
            else:
                copiar(cur, 'comprobante_vino', 'numero_comprobante,codigo_vino,cantidad,precio', filas)
            tiempos[modo] = round(perf_counter() - inicio, 3)
            if cur.execute("SELECT count(*) FROM bodegas_atuel.comprobante WHERE numero_comprobante LIKE 'B%' AND total=1039.50").fetchone()[0] != 2000:
                raise ValueError('El benchmark no produjo las mismas ventas válidas')
            raise psycopg.Rollback()
    return tiempos


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-prueba', required=True, help='Debe coincidir con PGDATABASE y empezar por bodegas_c_')
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--fecha-ref', type=date.fromisoformat, required=True)
    parser.add_argument('--comprobantes', type=int, default=100001)
    parser.add_argument('--benchmark', action='store_true')
    parser.add_argument('--reporte', type=Path)
    args = parser.parse_args()
    if args.fecha_ref.month == 2 and args.fecha_ref.day == 29:
        parser.error('Usar una fecha de referencia distinta del 29 de febrero')
    if args.comprobantes < 100001:
        parser.error('Se requieren al menos 100001 comprobantes para este perfil')
    total = perf_counter()
    with psycopg.connect('', autocommit=True) as conn:
        base, hoy = conn.execute('SELECT current_database(),CURRENT_DATE').fetchone()
        if base != args.base_prueba or not base.startswith('bodegas_c_'):
            raise ValueError('Conexión rechazada: no coincide la base de prueba identificada')
        if args.fecha_ref > hoy:
            raise ValueError('La fecha de referencia no puede ser futura')
        conn.execute('SET ROLE bodegas_propietario')
        conn.execute("SET timezone='America/Argentina/Buenos_Aires'")
        informe = {'base': base, 'seed': args.seed, 'fecha_ref': str(args.fecha_ref),
                   'psycopg': psycopg.__version__, 'Faker': FAKER_VERSION}
        if args.benchmark:
            antes = resumen(conn)
            informe['benchmark_2000_renglones_segundos'] = benchmark(conn, args.fecha_ref)
            if antes != resumen(conn):
                raise ValueError('El benchmark dejó cambios persistentes')
        else:
            with conn.transaction():
                tablas = conn.execute("SELECT tablename FROM pg_tables WHERE schemaname='bodegas_atuel' ORDER BY tablename").fetchall()
                if len(tablas) != 29:
                    raise ValueError('Instalar primero las 29 tablas vigentes')
                conn.execute(sql.SQL('LOCK TABLE {} IN ACCESS EXCLUSIVE MODE').format(
                    sql.SQL(',').join(sql.Identifier('bodegas_atuel', t[0]) for t in tablas)))
                for (tabla,) in tablas:
                    if conn.execute(sql.SQL('SELECT EXISTS(SELECT 1 FROM bodegas_atuel.{})').format(sql.Identifier(tabla))).fetchone()[0]:
                        raise ValueError('La base debe estar vacía; no se elimina ningún dato existente')
                # Las secuencias pueden avanzar incluso si una prueba hizo
                # ROLLBACK. Reiniciar solo la identity de esta base ya vacía.
                conn.execute('ALTER TABLE bodegas_atuel.auditoria_precios ALTER COLUMN id_auditoria RESTART WITH 1')
                cargar(conn.cursor(), args)
                informe['controles'] = validar(conn, args.fecha_ref)
            informe['generacion_carga_validacion_segundos'] = round(perf_counter() - total, 3)
            informe['tablas'] = resumen(conn)
            informe['huella_logica'] = hashlib.sha256(json.dumps(informe['tablas'], sort_keys=True).encode()).hexdigest()
        informe['total_segundos'] = round(perf_counter() - total, 3)
        texto = json.dumps(informe, ensure_ascii=False, indent=2)
        if args.reporte:
            args.reporte.write_text(texto + '\n', encoding='utf8')
        print(texto)


if __name__ == '__main__':
    main()
