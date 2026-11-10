from pathlib import Path

from playwright.sync_api import expect


def navigation(page, section):
    page.locator(f'nav a[href="#{section}"]').click()
    expect(page.locator('#' + section)).to_be_visible()


def fill_wine(page, code, percentage="100"):
    navigation(page, "gestion")
    fields = dict(codigo_vino=code,nombre_comercial=code,tipo="tinto",anada="2026",
                  presentacion_ml="750",graduacion_alcoholica="13",precio="100")
    for key, value in fields.items():
        page.locator(f'#vino-form [name="{key}"]').fill(value)
    page.locator('#vino-form [name=cuit_bodega]').select_option('20200000001')
    page.locator('#composicion select').select_option('1')
    page.locator('#composicion input').fill(percentage)


def transfer(page, number, lines):
    navigation(page, 'transferencias')
    page.locator('#transferencia-form [name=numero_solicitud]').fill(number)
    page.locator('#transferencia-form [name=id_sala]').select_option('1')
    page.get_by_role('button', name='Crear transferencia', exact=True).click()
    expect(page.locator('#transferencia-estado')).to_have_text('en_confeccion')
    expect(page.locator('#procesar-transferencia')).to_be_disabled()
    for code, qty in lines:
        page.locator('#transferencia-renglon [name=codigo_vino]').fill(code)
        page.locator('#transferencia-renglon [name=cantidad_botellas]').fill(str(qty))
        page.locator('#transferencia-renglon button').click()
        expect(page.locator('#transferencia-mensaje')).to_contain_text('Renglón guardado')
    page.locator('#terminar-transferencia').click()
    expect(page.locator('#transferencia-estado')).to_have_text('terminado')


def sale(page, number, lines):
    navigation(page, 'venta')
    page.locator('#venta-form [name=numero_comprobante]').fill(number)
    page.locator('#venta-form [name=id_sala]').select_option('1')
    page.locator('#venta-cliente').select_option('1')
    for index, (code, qty) in enumerate(lines):
        if index:
            page.locator('#agregar-venta').click()
        row = page.locator('#venta-lineas .line-row').nth(index)
        row.locator('[name=codigo_vino]').fill(code)
        row.locator('[name=cantidad]').fill(str(qty))
    page.locator('#confirmar-venta').click()


def test_01_catalogo_real(page):
    expect(page.locator('#vinos-body tr')).to_have_count(20)
    expect(page.locator('#vinos-body')).to_contain_text('Etiqueta de prueba 01')
    expect(page.locator('#anterior')).to_be_disabled()
    Path('.local/g').mkdir(exist_ok=True)
    page.screenshot(path='.local/g/catalogo.png', full_page=True)


def test_02_filtros_servidor(page):
    page.locator('#filtros [name=tipo]').fill('tinto')
    page.locator('#filtros [name=cepa]').select_option('1')
    page.locator('#filtros [name=bodega]').select_option('20200000001')
    page.locator('#filtros [name=anada]').fill('2025')
    with page.expect_response(lambda r: '/api/vinos?' in r.url and 'anada=2025' in r.url) as response:
        page.locator('#filtros button[type=submit]').click()
    assert response.value.status == 200
    expect(page.locator('#vinos-body tr')).to_have_count(1)
    expect(page.locator('#vinos-body')).to_contain_text('V1')
    page.locator('#filtros [name=tipo]').fill("tinto'; DROP TABLE vino; --")
    page.locator('#filtros button[type=submit]').click()
    expect(page.locator('#catalogo-mensaje')).to_contain_text('No hay vinos')


def test_03_paginacion(page):
    page.locator('#siguiente').click()
    expect(page.locator('#pagina-texto')).to_contain_text('Página 2')
    expect(page.locator('#vinos-body')).to_contain_text('Vino prueba')
    expect(page.locator('#anterior')).to_be_enabled()
    page.locator('#anterior').click()
    expect(page.locator('#pagina-texto')).to_contain_text('Página 1')


def test_04_detalle_y_contenido_seguro(page):
    page.locator('#codigo-busqueda').fill('UI23')
    page.locator('#buscar-codigo button').click()
    expect(page.locator('#detalle-dialog')).to_be_visible()
    expect(page.locator('#detalle-titulo')).to_have_text('<img src=x onerror="window.xss=true">')
    assert page.locator('#detalle-dialog img').count() == 0
    assert page.evaluate('window.xss') is None
    expect(page.locator('#detalle-contenido')).to_contain_text('Malbec')
    page.keyboard.press('Escape')
    expect(page.locator('#detalle-dialog')).not_to_be_visible()


def test_05_alta_edicion_y_baja(page, db):
    fill_wine(page, 'G-ALTA')
    page.locator('#guardar-vino').click()
    expect(page.locator('#vino-mensaje')).to_contain_text('guardado correctamente')
    assert db.execute("SELECT precio FROM vino WHERE codigo_vino='G-ALTA'").fetchone()['precio'] == 100
    page.locator('#eliminar-vino').click()
    page.locator('#cancelar-baja').click()
    assert db.execute("SELECT 1 FROM vino WHERE codigo_vino='G-ALTA'").fetchone()
    page.locator('#eliminar-vino').click(); page.locator('#confirmar-baja').click()
    expect(page.locator('#vino-mensaje')).to_contain_text('eliminado correctamente')
    fill_wine(page, 'G-EDITAR')
    page.locator('#guardar-vino').click()
    expect(page.locator('#vino-mensaje')).to_contain_text('guardado correctamente')
    page.locator('#vino-form [name=precio]').fill('120')
    page.locator('#guardar-vino').click()
    expect(page.locator('#vino-mensaje')).to_contain_text('guardado correctamente')
    page.wait_for_function("document.querySelector('#guardar-vino').disabled === false")
    assert db.execute("SELECT precio_nuevo FROM auditoria_precios WHERE codigo_vino='G-EDITAR'").fetchone()['precio_nuevo'] == 120
    page.locator('#eliminar-vino').click(); page.locator('#confirmar-baja').click()
    expect(page.locator('#vino-mensaje')).to_contain_text('dependencias')
    assert db.execute("SELECT 1 FROM composicion_vino_cepa WHERE codigo_vino='G-EDITAR'").fetchone()
    navigation(page, 'catalogo')
    page.locator('#catalogo-nuevo').click()
    expect(page.locator('#vino-form [name=codigo_vino]')).to_have_value('')
    expect(page.locator('#modo-vino')).to_have_text('Nueva etiqueta')


def test_06_composicion_80_rechazo_commit(page, db):
    fill_wine(page, 'G-80', '80')
    page.locator('#guardar-vino').click()
    expect(page.locator('#vino-mensaje')).to_contain_text('sumar 100')
    assert db.execute("SELECT 1 FROM vino WHERE codigo_vino='G-80'").fetchone() is None
    assert db.execute("SELECT 1 FROM stock_deposito WHERE codigo_vino='G-80'").fetchone() is None


def test_07_venta_valida(page, db):
    requests = []
    page.on('request', lambda r: requests.append(r) if r.method == 'POST' and r.url.endswith('/api/comprobantes') else None)
    with page.expect_request(lambda r: r.method == 'POST' and r.url.endswith('/api/comprobantes')) as sent:
        sale(page, 'G-VENTA', [('V1',2)])
    assert set(sent.value.post_data_json['renglones'][0]) == {'codigo_vino','cantidad'}
    assert 'descuento_aplicado' not in sent.value.post_data_json
    expect(page.locator('#venta-resultado')).to_be_visible()
    expect(page.locator('.receipt-total')).to_contain_text('180,00')
    assert db.execute("SELECT total FROM comprobante WHERE numero_comprobante='G-VENTA'").fetchone()['total'] == 180
    assert len(requests) == 1


def test_08_venta_sin_stock_atomicidad(page, db):
    before = db.execute("SELECT * FROM stock_sala ORDER BY id_sala,codigo_vino").fetchall()
    sale(page, 'G-SINSTOCK', [('V1',1),('V2',1)])
    expect(page.locator('#venta-mensaje')).to_contain_text('Stock insuficiente')
    expect(page.locator('#venta-resultado')).not_to_be_visible()
    assert db.execute("SELECT 1 FROM comprobante WHERE numero_comprobante='G-SINSTOCK'").fetchone() is None
    assert db.execute("SELECT * FROM stock_sala ORDER BY id_sala,codigo_vino").fetchall() == before


def test_09_transferencia_valida(page, db):
    before = db.execute("SELECT cantidad_botellas_disponibles AS n FROM stock_deposito WHERE codigo_vino='V1'").fetchone()['n']
    transfer(page, 'G-TRANS', [('V1',3)])
    expect(page.locator('#transferencia-renglon button')).to_be_disabled()
    page.locator('#procesar-transferencia').click()
    expect(page.locator('#transferencia-estado')).to_have_text('procesado')
    expect(page.locator('#procesar-transferencia')).to_be_disabled()
    assert db.execute("SELECT cantidad_botellas_disponibles AS n FROM stock_deposito WHERE codigo_vino='V1'").fetchone()['n'] == before-3


def test_10_transferencia_sin_stock(page, db):
    before = db.execute("SELECT * FROM stock_deposito ORDER BY codigo_vino").fetchall()
    transfer(page, 'G-TRANS-NO', [('V1',1),('V2',1)])
    page.locator('#procesar-transferencia').click()
    expect(page.locator('#transferencia-mensaje')).to_contain_text('Stock insuficiente')
    expect(page.locator('#transferencia-estado')).to_have_text('terminado')
    assert db.execute("SELECT * FROM stock_deposito ORDER BY codigo_vino").fetchall() == before


def test_11_reportes_reales_y_vacios(page):
    navigation(page, 'reportes')
    expect(page.locator('#top-vinos')).to_contain_text('Vino prueba')
    expect(page.locator('#grafico-ventas .bar-row')).to_have_count(1)
    expect(page.locator('#transportista')).to_contain_text('No hubo actividad')
    page.locator('#reporte-sala').select_option('1')
    expect(page.locator('#sin-stock')).to_contain_text('No hay resultados')
    page.screenshot(path='.local/g/reportes.png', full_page=True)


def test_12_movil_y_teclado(page):
    page.set_viewport_size({'width':390,'height':844})
    expect(page.locator('h1:visible')).to_have_text('Catálogo de vinos')
    page.screenshot(path='.local/g/movil.png', full_page=True)
    assert page.evaluate('document.documentElement.scrollWidth <= innerWidth'), page.evaluate("[...document.querySelectorAll('body,aside,nav,.workspace,.topbar,main,#catalogo,.filter-grid,.catalog-panel,.table-scroll,.lookup,footer')].map(e=>[e.tagName,e.className,e.clientWidth,e.scrollWidth,getComputedStyle(e).overflowX,Math.round(e.getBoundingClientRect().right)])")
    page.locator('#vinos-body button').first.click()
    expect(page.locator('#detalle-dialog')).to_be_visible()
    page.keyboard.press('Escape')
    expect(page.locator('#detalle-dialog')).not_to_be_visible()
    page.locator('#catalogo .table-scroll').evaluate('(element) => { element.scrollLeft = 0; }')
    page.screenshot(path='.local/g/movil.png', full_page=True)


def test_13_clientes_paginados(page):
    navigation(page, 'venta')
    expect(page.locator('#venta-cliente option')).to_have_count(21)
    page.locator('#clientes-siguiente').click()
    expect(page.locator('#clientes-pagina')).to_contain_text('Página 2')
    expect(page.locator('#venta-cliente')).to_contain_text('26 ·')
    expect(page.locator('#clientes-siguiente')).to_be_disabled()
    page.locator('#clientes-anterior').click()
    expect(page.locator('#clientes-pagina')).to_contain_text('Página 1')
    expect(page.locator('#clientes-anterior')).to_be_disabled()


def test_99_desconexion_real_api(page, web):
    web[1].terminate(); web[1].wait(timeout=10)
    page.locator('#salud').click()
    expect(page.locator('#salud-texto')).to_contain_text('Sin conexión')
    expect(page.locator('#aviso-global')).to_contain_text('no está disponible')
    expect(page.locator('#catalogo-mensaje')).to_contain_text('no está disponible')
