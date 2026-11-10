def test_catalogos_auxiliares_reales(client):
    r = client.get('/catalogos')
    assert r.status_code == 200
    data = r.json()
    assert data['salas'][0]['id_sala'] == 1
    assert data['cepas'][0]['nombre'] == 'Malbec'
    assert data['bodegas'][0]['cuit'] == '20200000001'
    assert set(data) == {'salas', 'cepas', 'bodegas'}
