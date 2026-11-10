"""Última botella con dos sesiones API; comparación académica aislada sin/con bloqueo."""
import argparse
import json
from pathlib import Path

from operar_docker import Docker


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base',required=True)
    parser.add_argument('--reporte',type=Path,default=Path('.local/h/concurrencia.json'))
    args = parser.parse_args()
    if not args.base.startswith('bodegas_h_pruebas_'):
        parser.error('Solo se permite una copia identificada bodegas_h_pruebas_*')
    docker = Docker()
    # Fixture real mediante documentos/procedimientos; no UPDATE directo de stock.
    docker.psql(args.base,"""BEGIN;
        SET LOCAL ROLE bodegas_propietario;
        SET LOCAL search_path=bodegas_atuel,pg_temp;
        INSERT INTO vino VALUES ('H-ULTIMA','Última botella - prueba H','tinto',2026,750,13,2,'20200000001');
        INSERT INTO composicion_vino_cepa VALUES ('H-ULTIMA',1,100);
        INSERT INTO ingreso(codigo_ingreso,fecha,codigo_transporte,cuit_bodega)
          VALUES ('H-ULTIMA',CURRENT_DATE,'T1','20200000001');
        INSERT INTO ingreso_vino VALUES ('H-ULTIMA','H-ULTIMA',1);
        UPDATE ingreso SET estado='terminado' WHERE codigo_ingreso='H-ULTIMA';
        CALL sp_procesar_ingreso('H-ULTIMA');
        INSERT INTO transferencia(numero_solicitud,id_sala) VALUES ('H-ULTIMA',1);
        INSERT INTO transferencia_vino VALUES ('H-ULTIMA','H-ULTIMA',1);
        UPDATE transferencia SET estado='terminado' WHERE numero_solicitud='H-ULTIMA';
        CALL sp_procesar_transferencia('H-ULTIMA');
        COMMIT;
        CREATE SCHEMA h_demostracion;
        CREATE TABLE h_demostracion.saldo_sin_triggers(id integer PRIMARY KEY,saldo integer NOT NULL);
        INSERT INTO h_demostracion.saldo_sin_triggers VALUES (1,1);
        GRANT USAGE ON SCHEMA h_demostracion TO bodegas_api;
        GRANT SELECT,UPDATE ON h_demostracion.saldo_sin_triggers TO bodegas_api;
    """)
    source = """import json,os,psycopg,threading,time
base = BASE_LITERAL
def conectar():
    return psycopg.connect(host=os.environ['DB_HOST'],port=os.environ['DB_PORT'],dbname=base,
      user=os.environ['DB_USER'],password=os.environ['DB_PASSWORD'],autocommit=True,
      options='-csearch_path=bodegas_atuel,pg_temp -clock_timeout=5000 -cstatement_timeout=10000')
resultados=[]
inicio=threading.Event()
def vender(nombre,primera):
    comienzo=time.monotonic()
    with conectar() as c:
        pid=c.execute('SELECT pg_backend_pid()').fetchone()[0]
        try:
            if not primera:
                assert inicio.wait(5)
            with c.transaction():
                c.execute('INSERT INTO comprobante(numero_comprobante,fecha,id_cliente,id_sala) VALUES (%s,CURRENT_DATE,1,1)',(nombre,))
                c.execute("INSERT INTO comprobante_vino VALUES (%s,'H-ULTIMA',1,(SELECT precio FROM vino WHERE codigo_vino='H-ULTIMA'))",(nombre,))
                if primera:
                    inicio.set(); time.sleep(1)
            resultados.append({'sesion':nombre,'pid':pid,'resultado':'commit','segundos':round(time.monotonic()-comienzo,3)})
        except psycopg.Error as e:
            resultados.append({'sesion':nombre,'pid':pid,'resultado':'rollback','sqlstate':e.sqlstate,
                'mensaje':e.diag.message_primary,'segundos':round(time.monotonic()-comienzo,3)})
threads=[threading.Thread(target=vender,args=('H-CONC-A',True)),threading.Thread(target=vender,args=('H-CONC-B',False))]
for t in threads: t.start()
for t in threads: t.join(15); assert not t.is_alive()
assert len(resultados)==2 and sum(r['resultado']=='commit' for r in resultados)==1
assert [r['sqlstate'] for r in resultados if r['resultado']=='rollback']==['23514']
with conectar() as c:
    saldo=c.execute("SELECT cantidad_stock FROM stock_sala WHERE id_sala=1 AND codigo_vino='H-ULTIMA'").fetchone()[0]
    cabeceras=c.execute("SELECT count(*) FROM comprobante WHERE numero_comprobante IN ('H-CONC-A','H-CONC-B')").fetchone()[0]
    lineas=c.execute("SELECT count(*) FROM comprobante_vino WHERE numero_comprobante IN ('H-CONC-A','H-CONC-B')").fetchone()[0]
    usuario=c.execute('SELECT current_user').fetchone()[0]
assert (saldo,cabeceras,lineas)==(0,1,1)

def comparar(con_bloqueo):
    with conectar() as c: c.execute('UPDATE h_demostracion.saldo_sin_triggers SET saldo=1 WHERE id=1')
    barrera=threading.Barrier(2); registros=[]
    def reservar():
        with conectar() as c:
            # Sin bloqueo ambos leen 1 antes de escribir un literal calculado.
            barrera.wait(timeout=5)
            with c.transaction():
                lectura=c.execute('SELECT saldo FROM h_demostracion.saldo_sin_triggers WHERE id=1'+(' FOR UPDATE' if con_bloqueo else '')).fetchone()[0]
                if not con_bloqueo: barrera.wait(timeout=5)
                if lectura>0:
                    c.execute('UPDATE h_demostracion.saldo_sin_triggers SET saldo=%s WHERE id=1',(lectura-1,))
                    registros.append('reserva confirmada')
                else: registros.append('sin saldo')
    sesiones=[threading.Thread(target=reservar) for _ in range(2)]
    for t in sesiones:t.start()
    for t in sesiones:t.join(10);assert not t.is_alive()
    assert len(registros)==2
    return registros
sin_bloqueo=comparar(False);con_bloqueo=comparar(True)
assert sin_bloqueo.count('reserva confirmada')==2
assert con_bloqueo.count('reserva confirmada')==1
print(json.dumps({'base':base,'usuario':usuario,'aislamiento':'read committed','stock_inicial':1,
 'sesiones':sorted(resultados,key=lambda x:x['sesion']),'stock_final':saldo,'cabeceras':cabeceras,'renglones':lineas,
 'comparacion_academica':{'tabla_aislada':'h_demostracion.saldo_sin_triggers','sin_bloqueo':sin_bloqueo,'con_SELECT_FOR_UPDATE':con_bloqueo},
 'modelo_de_negocio':'29 tablas intactas; sin deshabilitar triggers'},ensure_ascii=False))
""".replace('BASE_LITERAL',repr(args.base))
    text = docker.run(['docker','compose','exec','-T','api','python','-X','utf8','-c',"exec(__import__('sys').stdin.read())"],source)
    result = json.loads(text)
    args.reporte.parent.mkdir(parents=True,exist_ok=True)
    args.reporte.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False))


if __name__ == '__main__':
    main()
