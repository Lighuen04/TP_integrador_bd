"""Navegador → Nginx → FastAPI → PostgreSQL, usando una copia descartable.

No detiene servicios activos: crea API/frontend/red temporales y los retira al terminar.
"""
import argparse
import json
import os
import sys
import time
import uuid
from pathlib import Path

import httpx
from playwright.sync_api import expect, sync_playwright

from operar_docker import Docker, ROOT

sys.path.insert(0,str(ROOT))
from frontend.tests.test_frontend import fill_wine, navigation, sale, transfer


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base',required=True)
    parser.add_argument('--reporte',type=Path,default=Path('.local/h/integracion_docker.json'))
    args = parser.parse_args()
    if not args.base.startswith('bodegas_h_pruebas_'):
        parser.error('Usar una copia explícita bodegas_h_pruebas_*')
    docker = Docker()
    if len(docker.counts(args.base)) != 29:
        parser.error('La copia debe contener las 29 tablas')
    suffix = uuid.uuid4().hex[:10]
    net, api, front = ['bodegas-h-'+n+'-'+suffix for n in ('red','api','front')]
    db_container = docker.run(['docker','compose','ps','-q','db']).strip()
    # compose images devuelve la imagen del contenedor en uso; se construyen y
    # etiquetan imágenes nuevas sin reemplazar ni detener los servicios activos.
    project = docker.config['name']
    api_image, front_image = project+'-api', project+'-frontend'
    environment = dict(os.environ, DB_HOST='db',DB_PORT='5432',DB_NAME=args.base,
                       DB_USER=docker.env['DB_USER'],DB_PASSWORD=docker.env['DB_PASSWORD'])
    checks = []
    errors = []
    artifact = args.reporte.resolve().parent; artifact.mkdir(parents=True,exist_ok=True)
    connected = False
    try:
        docker.run(['docker','network','create',net])
        docker.run(['docker','network','connect','--alias','db',net,db_container]); connected = True
        command = ['docker','run','-d','--name',api,'--network',net,'--network-alias','api']
        for key in ('DB_HOST','DB_PORT','DB_NAME','DB_USER','DB_PASSWORD'):
            command += ['-e',key]
        docker.run(command+[api_image],env=environment)
        docker.run(['docker','run','-d','--name',front,'--network',net,'-p','127.0.0.1::80',front_image])
        port = json.loads(docker.run(['docker','inspect',front,'--format','{{json .NetworkSettings.Ports}}']))['80/tcp'][0]['HostPort']
        url = 'http://127.0.0.1:'+port
        with httpx.Client(base_url=url,timeout=5,trust_env=False) as client:
            for _ in range(50):
                try:
                    if client.get('/api/salud').status_code == 200:
                        break
                except httpx.RequestError:
                    pass
                time.sleep(.2)
            else:
                raise RuntimeError('API/Nginx temporales no alcanzaron salud')
            for path in ('/','/api/salud','/api/vinos','/api/catalogos','/docs','/openapi.json','/vinos'):
                assert client.get(path).status_code == 200,path
            for path in ('/.env','/api/database.py','/scripts/operar_docker.py','/redoc'):
                assert client.get(path).status_code == 404,path
            checks.append('salud, catálogo, catálogos auxiliares, Swagger y rutas sensibles')
        docker.run(['docker','exec',front,'nginx','-t'])
        with sync_playwright() as p:
            browser = p.chromium.launch(channel=os.environ.get('UI_BROWSER_CHANNEL'),headless=True)
            browser_version = browser.version
            page = browser.new_page(viewport={'width':1440,'height':1000},locale='es-AR')
            page.on('pageerror',lambda e: errors.append(str(e)))
            page.goto(url)
            page.wait_for_selector('#salud[data-estado="ok"]:not([disabled])')
            expect(page.locator('#vinos-body tr')).to_have_count(20)
            page.screenshot(path=str(artifact/'catalogo_docker.png'))
            checks.append('catálogo real de referencia y fixture de concurrencia cargados en navegador')
            page.locator('#siguiente').click()
            expect(page.locator('#pagina-texto')).to_contain_text('Página 2')
            page.locator('#filtros [name=anada]').fill('1900')
            page.locator('#filtros button[type=submit]').click()
            expect(page.locator('#catalogo-mensaje')).to_contain_text('No hay vinos')
            page.locator('#limpiar-filtros').click()
            page.locator('#codigo-busqueda').fill('V001')
            page.locator('#buscar-codigo button').click()
            expect(page.locator('#detalle-dialog')).to_be_visible()
            expect(page.locator('#detalle-contenido')).to_contain_text('Composición')
            page.keyboard.press('Escape')
            checks.append('filtros, paginación y detalle a través de Nginx')
            fill_wine(page,'H-E2E-80','80')
            page.locator('#guardar-vino').click()
            expect(page.locator('#vino-mensaje')).to_contain_text('sumar 100')
            assert docker.psql(args.base,"SELECT count(*) FROM bodegas_atuel.vino WHERE codigo_vino='H-E2E-80';").strip() == '0'
            page.locator('#nuevo-vino').click()
            fill_wine(page,'H-E2E-OK')
            page.locator('#guardar-vino').click()
            expect(page.locator('#vino-mensaje')).to_contain_text('guardado correctamente')
            page.locator('#vino-form [name=precio]').fill('120')
            page.locator('#guardar-vino').click()
            expect(page.locator('#vino-mensaje')).to_contain_text('guardado correctamente')
            page.wait_for_function("!document.querySelector('#guardar-vino').disabled")
            assert docker.psql(args.base,"SELECT precio_nuevo FROM bodegas_atuel.auditoria_precios WHERE codigo_vino='H-E2E-OK';").strip() == '120.00'
            checks.append('alta y edición con auditoría; composición 80 % rechazada al COMMIT')
            sale(page,'H-E2E-VENTA',[('V001',1)])
            expect(page.locator('#venta-resultado')).to_be_visible()
            expect(page.locator('.receipt-total')).to_contain_text('1.039,50')
            checks.append('venta válida: total histórico calculado por PostgreSQL 1039.50')
            before = docker.psql(args.base,"SELECT cantidad_stock FROM bodegas_atuel.stock_sala WHERE id_sala=1 AND codigo_vino='V001';")
            sale(page,'H-E2E-NO',[('V001',1),('H-ULTIMA',1)])
            expect(page.locator('#venta-mensaje')).to_contain_text('Stock insuficiente')
            assert docker.psql(args.base,"SELECT count(*) FROM bodegas_atuel.comprobante WHERE numero_comprobante='H-E2E-NO';").strip() == '0'
            assert docker.psql(args.base,"SELECT cantidad_stock FROM bodegas_atuel.stock_sala WHERE id_sala=1 AND codigo_vino='V001';") == before
            checks.append('venta sin stock rechazada sin cabecera ni débito parcial')
            transfer(page,'H-E2E-TRANS',[('V001',1)])
            page.locator('#procesar-transferencia').click()
            expect(page.locator('#transferencia-estado')).to_have_text('procesado')
            page.locator('#nueva-transferencia').click()
            transfer(page,'H-E2E-TRANS-NO',[('H-ULTIMA',1)])
            page.locator('#procesar-transferencia').click()
            expect(page.locator('#transferencia-mensaje')).to_contain_text('Stock insuficiente')
            expect(page.locator('#transferencia-estado')).to_have_text('terminado')
            checks.append('transferencia procesada por procedimiento y transferencia rechazada sin stock')
            navigation(page,'reportes')
            expect(page.locator('#top-vinos tbody tr')).to_have_count(10)
            expect(page.locator('#grafico-ventas .bar-row')).to_have_count(6)
            page.locator('#reporte-sala').select_option('6')
            expect(page.locator('#sin-stock tbody tr').first).to_be_visible()
            page.screenshot(path=str(artifact/'reportes_docker.png'))
            checks.append('reportes con diez vinos, seis salas y disponibilidad real')
            # Únicamente se detiene nuestra API temporal, nunca la del usuario.
            docker.run(['docker','stop',api])
            page.locator('#salud').click()
            expect(page.locator('#salud-texto')).to_contain_text('Sin conexión',timeout=10000)
            expect(page.locator('#aviso-global')).to_contain_text('no está disponible',timeout=10000)
            checks.append('caída real de API temporal comunicada en navegador')
            assert not errors, errors
            browser.close()
        result = {'base_descartable':args.base,'cadena':'Edge → Nginx → FastAPI → PostgreSQL Docker',
                  'navegador':browser_version,'comprobaciones':checks,'errores_javascript':errors,
                  'servicios_activos_del_usuario':'no detenidos; no escritos por estas pruebas',
                  'recursos_temporales':'contenedores y red eliminados; base de pruebas conservada'}
        args.reporte.parent.mkdir(parents=True,exist_ok=True)
        args.reporte.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print(json.dumps(result,ensure_ascii=False))
    finally:
        for name in (front,api):
            subprocess_args = ['docker','rm','-f',name]
            # Solo nombres aleatorios generados por esta ejecución; sin volúmenes.
            try: docker.run(subprocess_args)
            except RuntimeError: pass
        if connected:
            docker.run(['docker','network','disconnect',net,db_container])
        try: docker.run(['docker','network','rm',net])
        except RuntimeError: pass


if __name__ == '__main__':
    main()
