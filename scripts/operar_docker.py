"""Operaciones explícitas y no destructivas sobre PostgreSQL de Docker Compose.

Nunca elimina bases/volúmenes. Las restauraciones y cargas crean bases nuevas.
Las contraseñas se transmiten por entorno/stdin, nunca por argumentos o informes.
"""
import argparse
import json
import os
import re
import secrets
import subprocess
from datetime import date
from pathlib import Path

from psycopg import sql

ROOT = Path(__file__).resolve().parents[1]
IMAGE = 'bodegas-carga-tpi:local'


class Docker:
    def __init__(self):
        self.secrets = []
        self.config = json.loads(self.run(['docker', 'compose', 'config', '--format', 'json']))
        self.env = self.config['services']['db']['environment']
        self.base = self.config['services']['api']['environment']['DB_NAME']
        self.secrets += [self.env['POSTGRES_PASSWORD'], self.env['DB_PASSWORD']]

    def run(self, args, data=None, env=None):
        result = subprocess.run(args, input=data, text=True, encoding='utf-8',
                                capture_output=True, cwd=ROOT, env=env)
        if result.returncode:
            message = result.stderr[-1800:]
            for secret in self.secrets:
                if secret:
                    message = message.replace(secret, '[secreto omitido]')
            raise RuntimeError(f'Falló {args[0]} (código {result.returncode}): {message}')
        return result.stdout

    def psql(self, base, statement):
        return self.run(['docker','compose','exec','-T','db','psql','-X','-qAt',
                         '-U','postgres','-d',base,'-v','ON_ERROR_STOP=1'], statement)

    def counts(self, base=None):
        base = base or self.base
        tables = self.psql(base, "SELECT tablename FROM pg_tables WHERE schemaname='bodegas_atuel' ORDER BY tablename;").splitlines()
        statements = [sql.SQL("SELECT json_build_object('tabla',{},'filas',count(*)) FROM bodegas_atuel.{};")
                      .format(sql.Literal(t),sql.Identifier(t)).as_string() for t in tables]
        rows = self.psql(base, '\n'.join(statements)).splitlines() if tables else []
        return {row['tabla']: row['filas'] for row in map(json.loads, rows)}

    def create(self, name):
        if not re.fullmatch(r'bodegas_(c_docker|h_restaurada|h_pruebas)_[a-z0-9_]+', name):
            raise ValueError('Usar una base nueva bodegas_c_docker_*, bodegas_h_restaurada_* o bodegas_h_pruebas_*')
        # CREATE falla si ya existe. Nunca DROP/TRUNCATE ni sobrescritura.
        self.psql('postgres', sql.SQL('CREATE DATABASE {} TEMPLATE template0;').format(sql.Identifier(name)).as_string())

    def build_tools(self):
        self.run(['docker','build','-t',IMAGE,'-f','database/seed/Dockerfile','.'])

    def install(self, name):
        self.create(name)
        for p in sorted((ROOT/'database').glob('0[1-7]_*.sql')) + [ROOT/'database/10_api_baja_vino.sql']:
            self.psql(name,p.read_text(encoding='utf-8'))

    def sql_tests(self, name):
        if not name.startswith('bodegas_h_pruebas_'):
            raise ValueError('Las suites SQL requieren una base nueva bodegas_h_pruebas_*')
        self.install(name)
        results = []
        for filename in ('08_pruebas_integridad.sql','09_pruebas_reglas_negocio.sql'):
            self.psql(name,(ROOT/'database'/filename).read_text(encoding='utf-8'))
            results.append({'archivo':filename,'exit_code':0})
        if any(self.counts(name).values()):
            raise ValueError('Las suites dejaron filas sin revertir')
        return {'base_descartable':name,'suites':results,'29_tablas_sin_fixtures_tras_rollback':True}

    def tool(self, base, args, source=None):
        container = self.run(['docker','compose','ps','-q','db']).strip()
        networks = json.loads(self.run(['docker','inspect',container,'--format','{{json .NetworkSettings.Networks}}']))
        if len(networks) != 1:
            raise ValueError('Identificar una única red Compose antes de ejecutar herramientas')
        environment = dict(os.environ, PGHOST='db', PGPORT='5432', PGDATABASE=base,
                           PGUSER='postgres', PGPASSWORD=self.env['POSTGRES_PASSWORD'])
        command = ['docker','run','--rm','-i','--network',next(iter(networks))]
        for name in ('PGHOST','PGPORT','PGDATABASE','PGUSER','PGPASSWORD'):
            command += ['-e',name]  # Docker lee el valor del entorno del proceso.
        if source is not None:
            command += ['--entrypoint','python',IMAGE,'-X','utf8','-c',"exec(__import__('sys').stdin.read())"]
        else:
            command += [IMAGE] + args
        return self.run(command, source, environment)

    def validate(self, base, reference):
        source = f"""import sys,json,psycopg,hashlib
from datetime import date
sys.path.insert(0,'/tools/seed')
from generar_datos import resumen,validar
with psycopg.connect('',autocommit=True) as conn:
    conn.execute("SET search_path=bodegas_atuel,public")
    conn.execute("SET timezone='America/Argentina/Buenos_Aires'")
    digest=hashlib.sha256()
    with conn.cursor().copy('COPY (SELECT * FROM bodegas_atuel.permiso_exportacion ORDER BY codigo_permiso COLLATE "C") TO STDOUT') as copy:
        for block in copy: digest.update(block)
    print(json.dumps({{'tablas':resumen(conn),'controles':validar(conn,date.fromisoformat({str(reference)!r})),
        'permiso_exportacion_sha256_collate_C':digest.hexdigest()}},ensure_ascii=False))
"""
        return json.loads(self.tool(base, [], source))

    def load(self, name, reference):
        current = self.counts()
        if len(current) != 29 or any(current.values()):
            raise ValueError('La base activa debe tener las 29 tablas vacías; conservar datos existentes y usar otra estrategia explícita')
        self.install(name)
        self.build_tools()
        return json.loads(self.tool(name, ['--base-prueba',name,'--seed','42','--fecha-ref',str(reference)]))

    def backup(self, output):
        output = output.resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        # xb evita sobrescribir incluso un respaldo con el mismo nombre.
        with output.open('xb') as destination:
            result = subprocess.run(['docker','compose','exec','-T','db','pg_dump',
                '-U','postgres','-d',self.base,'--format=custom'], cwd=ROOT, stdout=destination, stderr=subprocess.PIPE)
        if result.returncode:
            raise RuntimeError('pg_dump falló; el archivo incompleto se conserva para diagnóstico, no usarlo para restaurar')
        return {'base':self.base,'archivo':str(output),'bytes':output.stat().st_size}

    def restore(self, name, source):
        if not source.is_file():
            raise ValueError('No existe el respaldo')
        self.create(name)
        with source.open('rb') as backup:
            result = subprocess.run(['docker','compose','exec','-T','db','pg_restore',
                '-U','postgres','-d',name,'--single-transaction','--exit-on-error'],
                stdin=backup, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, cwd=ROOT)
        if result.returncode:
            raise RuntimeError('La restauración falló y su transacción se revirtió; no se modifica la base original')
        return {'base_restaurada':name,'conteos':self.counts(name)}

    def update_env(self, values):
        path = ROOT/'.env'
        text = path.read_text(encoding='utf-8-sig')
        for key, value in values.items():
            if re.search(r'^'+key+r'=',text,re.M):
                text = re.sub(r'^'+key+r'=.*$', key+'='+value,text,flags=re.M)
            else:
                text += '\n'+key+'='+value+'\n'
        # Nunca imprimir el archivo, que contiene secretos.
        temporary = ROOT/'.env.operacion.tmp'
        temporary.write_text(text,encoding='utf-8')
        temporary.replace(path)

    def activate(self, name):
        if len(self.counts(name)) != 29 or not all(self.counts(name).values()):
            raise ValueError('La base de demostración debe existir y contener las 29 tablas pobladas')
        self.update_env({'DB_NAME':name})
        self.run(['docker','compose','up','-d','--no-deps','--force-recreate','api','frontend'])
        return {'base_activa':name,'datos_anteriores':'conservados; no se recrea el volumen'}

    def rotate(self):
        new_admin, new_api = secrets.token_urlsafe(36), secrets.token_urlsafe(36)
        self.secrets += [new_admin,new_api]
        statement = "SET log_statement='none'; SET log_min_error_statement='panic';\n"
        for role, password in [('postgres',new_admin),(self.env['DB_USER'],new_api)]:
            statement += sql.SQL('ALTER ROLE {} PASSWORD {};\n').format(sql.Identifier(role),sql.Literal(password)).as_string()
        self.psql('postgres',statement)  # Solo stdin, nunca argv ni logs.
        self.update_env({'POSTGRES_PASSWORD':new_admin,'DB_PASSWORD':new_api})
        self.run(['docker','compose','up','-d','--no-deps','--force-recreate','api','frontend'])
        return {'credenciales':'rotadas en PostgreSQL y .env; valores no incluidos','volumen':'conservado'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operacion',choices=['conteos','cargar','validar','backup','restaurar','activar','rotar-credenciales','probar-sql'])
    parser.add_argument('--base')
    parser.add_argument('--archivo',type=Path)
    parser.add_argument('--fecha-ref',type=date.fromisoformat,default=date(2026,11,9))
    parser.add_argument('--reporte',type=Path)
    args = parser.parse_args()
    docker = Docker()
    if args.operacion in {'cargar','restaurar','activar','probar-sql'} and not args.base:
        parser.error('La operación requiere --base explícita')
    if args.operacion in {'backup','restaurar'} and not args.archivo:
        parser.error('La operación requiere --archivo explícito')
    if args.operacion == 'conteos':
        result = {'base':args.base or docker.base,'conteos':docker.counts(args.base)}
    elif args.operacion == 'cargar':
        result = docker.load(args.base,args.fecha_ref)
    elif args.operacion == 'validar':
        docker.build_tools()
        result = docker.validate(args.base or docker.base,args.fecha_ref)
    elif args.operacion == 'backup':
        result = docker.backup(args.archivo)
    elif args.operacion == 'restaurar':
        result = docker.restore(args.base,args.archivo)
    elif args.operacion == 'activar':
        result = docker.activate(args.base)
    elif args.operacion == 'probar-sql':
        result = docker.sql_tests(args.base)
    else:
        result = docker.rotate()
    text = json.dumps(result,ensure_ascii=False,indent=2)
    if args.reporte:
        args.reporte.parent.mkdir(parents=True,exist_ok=True)
        args.reporte.write_text(text+'\n',encoding='utf-8')
    print(text)


if __name__ == '__main__':
    main()
