"""Prueba aislada del perfil HTTPS/verify-full con CA privada de laboratorio.

No crea recursos externos ni cambia el proyecto activo. No instala confianza
en el sistema ni elimina volúmenes. Un éxito local NO acredita HTTPS público.
"""
import argparse
import json
import os
import secrets
import shutil
import ssl
import time
import uuid
from pathlib import Path

import httpx

from operar_docker import Docker, ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--openssl',default=shutil.which('openssl') or 'C:/Program Files/Git/usr/bin/openssl.exe')
    parser.add_argument('--reporte',type=Path,default=Path('.local/i/tls.json'))
    args = parser.parse_args()
    if not Path(args.openssl).is_file():
        parser.error('Configurar --openssl con el ejecutable local; no se descarga ni contrata ningún servicio')
    docker = Docker()
    ident = uuid.uuid4().hex[:10]
    project = 'bodegas_i_tls_'+ident
    folder = ROOT/'.local/i'/project
    certs = folder/'certificados'; certs.mkdir(parents=True)
    private = folder/'privado'; private.mkdir()
    ca_key,ca_cert = private/'ca.key',certs/'ca.crt'
    openssl_config = folder/'openssl.cnf'
    openssl_config.write_text('[req]\ndistinguished_name=dn\nx509_extensions=ca_ext\nprompt=no\n[dn]\nCN=Laboratorio\n[ca_ext]\nbasicConstraints=critical,CA:true\nkeyUsage=critical,keyCertSign,cRLSign\n',encoding='utf-8')
    def openssl(*argv):
        docker.run([args.openssl,*map(str,argv)],env=dict(os.environ,OPENSSL_CONF=str(openssl_config)))
    openssl('req','-x509','-newkey','rsa:2048','-nodes','-keyout',ca_key,'-out',ca_cert,
            '-days','2','-subj','/CN=Atuel CA laboratorio I')
    for name,common,san in [('postgres','db','DNS:db'),('web','localhost','DNS:localhost,IP:127.0.0.1')]:
        extension = certs/(name+'.ext')
        extension.write_text('subjectAltName='+san+'\nextendedKeyUsage=serverAuth\nbasicConstraints=critical,CA:false\n',encoding='utf-8')
        openssl('req','-new','-newkey','rsa:2048','-nodes','-keyout',certs/(name+'.key'),
                '-out',certs/(name+'.csr'),'-subj','/CN='+common)
        openssl('x509','-req','-in',certs/(name+'.csr'),'-CA',ca_cert,'-CAkey',ca_key,
                '-CAcreateserial','-out',certs/(name+'.crt'),'-days','2','-extfile',extension)
    openssl('req','-x509','-newkey','rsa:2048','-nodes','-keyout',private/'ca_no_confiable.key',
            '-out',certs/'ca_no_confiable.crt','-days','2','-subj','/CN=CA distinta')
    postgres_image = docker.config['services']['db']['image']
    uid = docker.run(['docker','run','--rm','--entrypoint','id',postgres_image,'-u','postgres']).strip()
    gid = docker.run(['docker','run','--rm','--entrypoint','id',postgres_image,'-g','postgres']).strip()
    volume_names = {name:project+'_'+name for name in ('tls_db','tls_api','tls_web')}
    for name,volume in volume_names.items():
        docker.run(['docker','volume','create',volume])
        copy_files = {'tls_db':['postgres.crt','postgres.key'],
                      'tls_api':['ca.crt','ca_no_confiable.crt'],
                      'tls_web':['web.crt','web.key']}[name]
        command = 'cp '+ ' '.join('/entrada/'+name for name in copy_files)+' /salida/; chmod 644 /salida/*.crt'
        if name == 'tls_db':
            command += '; chown '+uid+':'+gid+' /salida/postgres.key; chmod 600 /salida/postgres.key'
        if name == 'tls_web':
            command += '; chmod 600 /salida/web.key'
        docker.run(['docker','run','--rm','--user','root','-v',volume+':/salida',
                    '-v',str(certs)+':/entrada:ro','--entrypoint','sh',postgres_image,'-ec',command])
    # En Windows los bind mounts no representan los modos POSIX de las claves.
    # El override de laboratorio usa volúmenes propios para probar permisos reales.
    mounts = []
    for mount in docker.config['services']['db']['volumes']:
        source = mount['source']; target = mount['target']
        mounts.append('      - '+json.dumps(source+':'+target+(':ro' if mount.get('read_only') else '')))
    mounts.append('      - '+project+'_tls_db:/run/tls:ro')
    api_image = docker.config['name']+'-api'
    front_image = docker.config['name']+'-frontend'
    override = folder/'laboratorio.yml'
    override.write_text('''services:
  db:
    volumes: !override
'''+ '\n'.join(mounts)+'''
  api:
    image: '''+api_image+'''
    pull_policy: never
    ports: !override []
    volumes: !override
      - '''+project+'''_tls_api:/run/tls:ro
  frontend:
    image: '''+front_image+'''
    pull_policy: never
    ports: !override
      - "127.0.0.1::443"
    volumes: !override
      - '''+json.dumps(str(ROOT/'deploy/nginx.https.conf')+':/etc/nginx/conf.d/default.conf:ro')+'''
      - '''+project+'''_tls_web:/run/tls:ro
volumes:
'''+''.join(f'  {volume}:\n    external: true\n' for volume in volume_names.values()),encoding='utf-8')
    admin_password,api_password = secrets.token_urlsafe(36),secrets.token_urlsafe(36)
    docker.secrets += [admin_password,api_password]
    environment = dict(os.environ,TLS_DIR=str(certs),DB_NAME='bodegas_i_tls',
                       DB_USER='bodegas_app',DB_PASSWORD=api_password,POSTGRES_PASSWORD=admin_password)
    compose = ['docker','compose','-p',project,'-f','docker-compose.yml','-f','deploy/compose.https.yml','-f',str(override)]
    try:
        docker.run(compose+['config','--quiet'],env=environment)
        configuration=json.loads(docker.run(compose+['config','--format','json'],env=environment))
        assert configuration['volumes']['postgres_data']['name'] != docker.config['volumes']['postgres_data']['name']
        docker.run(['docker','compose','build','api'])
        docker.run(compose+['up','-d','--no-build'],env=environment)
        policies={}
        for service in ('db','api','frontend'):
            container=docker.run(compose+['ps','-q',service],env=environment).strip()
            policy=json.loads(docker.run(['docker','inspect',container,'--format','{{json .HostConfig.RestartPolicy}}']))
            assert policy['Name']=='unless-stopped'
            policies[service]=policy['Name']
        front_id = docker.run(compose+['ps','-q','frontend'],env=environment).strip()
        ports = json.loads(docker.run(['docker','inspect',front_id,'--format','{{json .NetworkSettings.Ports}}']))
        port = ports['443/tcp'][0]['HostPort']
        url = 'https://127.0.0.1:'+port
        context = ssl.create_default_context(cafile=str(ca_cert))
        with httpx.Client(verify=context,trust_env=False,timeout=10) as client:
            for _ in range(30):
                try:
                    response=client.get(url+'/api/salud')
                    if response.status_code == 200: break
                except httpx.RequestError: pass
                time.sleep(.3)
            else: raise AssertionError('No se alcanzó salud a través de HTTPS')
            statuses={path:client.get(url+path).status_code for path in ('/','/api/salud','/api/vinos','/docs','/openapi.json')}
            assert all(status==200 for status in statuses.values())
        try:
            httpx.get(url+'/api/salud',trust_env=False,timeout=5)
        except httpx.ConnectError as error:
            assert 'certificate' in str(error).lower(),str(error)
            public_trust=False
        else:
            raise AssertionError('La CA privada no debe estar instalada como confianza pública')
        source = '''import json,os,socket,psycopg
cfg=dict(host='db',port=5432,dbname=os.environ['DB_NAME'],user=os.environ['DB_USER'],
 password=os.environ['DB_PASSWORD'],sslmode='verify-full',sslrootcert='/run/tls/ca.crt',connect_timeout=3)
with psycopg.connect(**cfg) as c:
 row=c.execute('SELECT ssl,version,cipher FROM pg_stat_ssl WHERE pid=pg_backend_pid()').fetchone()
 assert row[0]
 result=dict(ssl=row[0],version=row[1],cipher=row[2],usuario=c.execute('SELECT current_user').fetchone()[0])
for case,changes in [('nombre_incorrecto',dict(host='identidad-incorrecta.invalid',hostaddr=socket.gethostbyname('db'))),
 ('CA_incorrecta',dict(sslrootcert='/run/tls/ca_no_confiable.crt'))]:
 try:
  with psycopg.connect(**dict(cfg,**changes)) as c: c.execute('SELECT 1')
 except psycopg.OperationalError as e:
  assert 'certificate' in str(e).lower(),str(e)
  result[case]='rechazada'
 else: raise AssertionError('verify-full permitió identidad o CA incorrecta')
print(json.dumps(result))
'''
        text=docker.run(compose+['exec','-T','api','python','-c',"exec(__import__('sys').stdin.read())"],source,environment)
        pg=json.loads(text)
        mode=docker.run(compose+['exec','-T','db','stat','-c','%a:%U','/run/tls/postgres.key'],env=environment).strip()
        assert mode=='600:postgres',mode
        docker.run(compose+['exec','-T','frontend','nginx','-t'],env=environment)
        result={'perfil':'deploy/compose.https.yml','ambito':'laboratorio local aislado',
          'proyecto':project,'https_privado_verificado':statuses,'CA_publicamente_confiable':public_trust,
          'postgres':pg,'permiso_clave_postgres':mode,'politicas_reinicio_verificadas':policies,
          'adaptacion_windows':'puertos efímeros loopback y volúmenes TLS propios con permisos POSIX',
          'volumen_datos_conservado':project+'_postgres_data','volumenes_certificados_conservados':list(volume_names.values()),
          'produccion_publica_verificada':False,'proyecto_activo_modificado':False}
        args.reporte.parent.mkdir(parents=True,exist_ok=True)
        args.reporte.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print(json.dumps(result,ensure_ascii=False))
    finally:
        # No -v: se conservan todos los volúmenes; solo se detienen nuestros contenedores.
        docker.run(compose+['down'],env=environment)


if __name__ == '__main__':
    main()
