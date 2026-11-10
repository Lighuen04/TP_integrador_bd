"""Etapa 4: medir exclusivamente una copia descartable de la carga de fase C."""
import argparse
import hashlib
import json
import os
import platform
import random
import re
import shlex
import statistics
import sys
from pathlib import Path

import psycopg
from psycopg import sql

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'database' / 'seed'))
from generar_datos import resumen, benchmark


def consultas(conn):
    seleccionadas = {}
    for archivo in ('select', 'delete'):
        texto = (ROOT / 'consultas' / (archivo + '.sql')).read_text(encoding='utf8')
        variables = {}
        for linea in texto.splitlines():
            if linea.startswith('\\set ') and 'ON_ERROR_STOP' not in linea:
                _, clave, valor = shlex.split(linea)
                variables[clave] = valor
        texto = '\n'.join(l for l in texto.splitlines() if not l.startswith('\\'))
        for clave in sorted(variables, key=len, reverse=True):
            literal = sql.Literal(variables[clave]).as_string(conn)
            texto = texto.replace(":'" + clave + "'", literal)
            texto = re.sub(':' + clave + r'\b', lambda _: literal, texto)
        marcas = list(re.finditer(r'^-- ([SD]\d+)\.', texto, re.M))
        for i, marca in enumerate(marcas):
            codigo = marca[1]
            if codigo not in ('S1', 'S2', 'S3', 'S4', 'S5', 'S8', 'S10', 'S11', 'D4'):
                continue
            bloque = texto[marca.start():marcas[i+1].start() if i+1 < len(marcas) else len(texto)]
            if codigo == 'D4':
                seleccionadas[codigo] = re.search(r'DELETE FROM cliente.*?RETURNING c.id_cliente;', bloque, re.S)[0]
            else:
                bloque = '\n'.join(l for l in bloque.splitlines() if not l.lstrip().startswith('--'))
                for j, consulta in enumerate(q.strip() for q in bloque.split(';') if q.strip()):
                    seleccionadas[codigo + ('_' + str(j+1) if codigo == 'S11' else '')] = consulta
    return seleccionadas


def nodos(plan):
    yield plan
    for hijo in plan.get('Plans', []):
        yield from nodos(hijo)


def explicar(conn, codigo, consulta):
    try:
        conn.execute('BEGIN')
        conn.execute('SET CONSTRAINTS ALL IMMEDIATE')
        return conn.execute('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' + consulta).fetchone()[0][0]
    finally:
        # EXPLAIN ANALYZE de D4 sí elimina filas: el rollback es obligatorio.
        conn.execute('ROLLBACK')


def medir(conn, queries, repeticiones):
    muestras = {k: [] for k in queries}
    for codigo, consulta in queries.items():
        explicar(conn, codigo, consulta)  # calentamiento excluido
    orden = list(queries)
    rng = random.Random(42)
    for _ in range(repeticiones):
        rng.shuffle(orden)
        for codigo in orden:
            muestras[codigo].append(explicar(conn, codigo, queries[codigo]))
    salida = {}
    for codigo, planes in muestras.items():
        tiempos = [p['Execution Time'] for p in planes]
        mediana = statistics.median(tiempos)
        representativo = min(planes, key=lambda p: abs(p['Execution Time'] - mediana))
        raiz = representativo['Plan']
        salida[codigo] = {
            'ejecucion_ms': tiempos, 'mediana_ms': mediana,
            'min_ms': min(tiempos), 'max_ms': max(tiempos),
            'planificacion_mediana_ms': statistics.median(p['Planning Time'] for p in planes),
            'filas_resultado': raiz['Actual Rows'],
            'shared_hit': raiz['Shared Hit Blocks'], 'shared_read': raiz['Shared Read Blocks'],
            'indices_usados': sorted({n['Index Name'] for n in nodos(raiz) if 'Index Name' in n}),
            'recorridos': sorted({n['Node Type'] for n in nodos(raiz) if 'Scan' in n['Node Type']}),
            'plan_completo': representativo,
        }
        print(codigo, round(mediana, 3), 'ms', flush=True)
    return salida


def costo_escritura(conn, fecha, repeticiones):
    resultados = []
    for i in range(repeticiones + 1):
        # Igual limpieza, índices y triggers; la muestra hace sus propios rollback.
        conn.execute('VACUUM (ANALYZE)')
        muestra = benchmark(conn, fecha)
        if i:
            resultados.append(muestra)
    return {modo: {'segundos': [r[modo] for r in resultados],
                   'mediana_s': statistics.median(r[modo] for r in resultados)}
            for modo in ('fila', 'copy')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-prueba', required=True)
    parser.add_argument('--salida', type=Path, required=True)
    parser.add_argument('--repeticiones', type=int, default=7)
    args = parser.parse_args()
    if not args.base_prueba.startswith('bodegas_e_') or args.repeticiones < 5:
        parser.error('Usar base descartable bodegas_e_* y al menos cinco repeticiones')
    with psycopg.connect('', autocommit=True) as conn:
        base, fecha, version = conn.execute('SELECT current_database(),CURRENT_DATE,version()').fetchone()
        if base != args.base_prueba:
            raise ValueError('La base conectada no es la copia descartable identificada')
        conn.execute('SET ROLE bodegas_propietario')
        conn.execute('SET search_path=bodegas_atuel,public')
        originales = resumen(conn)
        if originales['comprobante']['filas'] != 100001:
            raise ValueError('Se espera el perfil completo de fase C, sin purgas')
        queries = consultas(conn)
        resultado = {'base': base, 'fecha': str(fecha), 'version': version,
                     'python': platform.python_version(), 'plataforma': platform.platform(),
                     'procesador': platform.processor(), 'cpus_logicas': os.cpu_count(),
                     'repeticiones': args.repeticiones, 'consultas': queries, 'tablas': originales}
        nombres = ['shared_buffers','work_mem','effective_cache_size','random_page_cost','seq_page_cost',
                   'max_parallel_workers_per_gather','max_parallel_workers','jit','default_transaction_isolation',
                   'enable_seqscan','enable_indexscan','enable_indexonlyscan','enable_bitmapscan']
        resultado['configuracion'] = dict(conn.execute('SELECT name,setting FROM pg_settings WHERE name=ANY(%s)', (nombres,)))
        # No se eliminan PK, UNIQUE ni restricciones. Solo índices secundarios
        # de esta copia, con una comprobación explícita del nombre de la base.
        secundarios = conn.execute("SELECT i.indexrelid::regclass::text FROM pg_index i JOIN pg_class t ON t.oid=i.indrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='bodegas_atuel' AND NOT i.indisprimary AND NOT i.indisunique").fetchall()
        for (indice,) in secundarios:
            conn.execute('DROP INDEX ' + indice)
        resultado['indices_baseline'] = conn.execute("SELECT count(*) FROM pg_indexes WHERE schemaname='bodegas_atuel'").fetchone()[0]
        assert resultado['indices_baseline'] == 33
        conn.execute('VACUUM (ANALYZE)')
        print('ESCENARIO A: PK y UNIQUE', flush=True)
        resultado['antes'] = medir(conn, queries, args.repeticiones)
        resultado['escritura_antes'] = costo_escritura(conn, fecha, 5)
        assert resumen(conn) == originales
        conn.execute((ROOT / 'database' / '06_indices.sql').read_text(encoding='utf8'))
        conn.execute('VACUUM (ANALYZE)')
        print('ESCENARIO B: índices definitivos', flush=True)
        resultado['despues'] = medir(conn, queries, args.repeticiones)
        resultado['escritura_despues'] = costo_escritura(conn, fecha, 5)
        assert resumen(conn) == originales
        # La FK de D4 usa planes internos que no son nodos del plan principal.
        conn.execute('SELECT pg_stat_force_next_flush()')
        conn.execute('SELECT pg_stat_clear_snapshot()')
        antes_fk = conn.execute("SELECT idx_scan FROM pg_stat_user_indexes WHERE indexrelname='ix_comprobante_cliente_fecha'").fetchone()[0]
        explicar(conn, 'D4', queries['D4'])
        conn.execute('SELECT pg_stat_force_next_flush()')
        conn.execute('SELECT pg_stat_clear_snapshot()')
        despues_fk = conn.execute("SELECT idx_scan FROM pg_stat_user_indexes WHERE indexrelname='ix_comprobante_cliente_fecha'").fetchone()[0]
        resultado['d4_indice_fk_verificado'] = {'indice': 'ix_comprobante_cliente_fecha',
            'idx_scan_antes': antes_fk, 'idx_scan_despues': despues_fk, 'incremento': despues_fk-antes_fk}
        assert despues_fk > antes_fk
        # Candidato descartado: mismo dataset, misma consulta S8, sin forzar plan.
        conn.execute('VACUUM (ANALYZE)')
        conn.execute('CREATE INDEX ix_e_brin_fecha ON comprobante USING brin(fecha)')
        conn.execute('ANALYZE comprobante')
        resultado['descartado_brin'] = medir(conn, {'S8': queries['S8']}, args.repeticiones)['S8']
        resultado['descartado_brin']['bytes'] = conn.execute("SELECT pg_relation_size('ix_e_brin_fecha')").fetchone()[0]
        resultado['descartado_brin']['correlacion_fecha'] = conn.execute("SELECT correlation FROM pg_stats WHERE schemaname='bodegas_atuel' AND tablename='comprobante' AND attname='fecha'").fetchone()[0]
        conn.execute('DROP INDEX ix_e_brin_fecha')
        resultado['indices_finales'] = [dict(zip(('nombre','bytes','definicion'), r)) for r in conn.execute("SELECT indexname,pg_relation_size(indexname::regclass),indexdef FROM pg_indexes WHERE schemaname='bodegas_atuel' ORDER BY indexname")]
        resultado['huellas_finales_iguales'] = resumen(conn) == originales
        resultado['fuentes_sha256'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__).resolve(), ROOT/'database/06_indices.sql', ROOT/'consultas/select.sql', ROOT/'consultas/delete.sql']}
        args.salida.parent.mkdir(parents=True, exist_ok=True)
        args.salida.write_text(json.dumps(resultado, ensure_ascii=False, indent=2) + '\n', encoding='utf8')


if __name__ == '__main__':
    main()
