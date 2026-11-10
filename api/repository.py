"""SQL directo. Los únicos identificadores variables proceden de listas internas."""
from fastapi import HTTPException
from psycopg import sql


def uno(cur):
    fila = cur.fetchone()
    if fila is None:
        raise HTTPException(404, "Recurso inexistente")
    return fila


def vinos(conn, limite, offset, tipo, cepa, bodega, anada):
    return conn.execute("""SELECT v.* FROM vino v
        WHERE (%s::text IS NULL OR v.tipo=%s)
          AND (%s::integer IS NULL OR EXISTS (SELECT 1 FROM composicion_vino_cepa c
               WHERE c.codigo_vino=v.codigo_vino AND c.id_cepa=%s))
          AND (%s::text IS NULL OR v.cuit_bodega=%s)
          AND (%s::integer IS NULL OR v.anada=%s)
        ORDER BY v.codigo_vino LIMIT %s OFFSET %s""",
        (tipo, tipo, cepa, cepa, bodega, bodega, anada, anada, limite, offset)).fetchall()


def vino(conn, codigo):
    # S9: asociaciones independientes para evitar multiplicar las dos N:M.
    return uno(conn.execute("""SELECT v.*, b.razon_social AS bodega,
        COALESCE((SELECT jsonb_agg(jsonb_build_object('id_cepa',c.id_cepa,
          'cepa',c.nombre,'porcentaje_corte',cc.porcentaje_corte) ORDER BY c.id_cepa)
          FROM composicion_vino_cepa cc JOIN cepa c USING(id_cepa)
          WHERE cc.codigo_vino=v.codigo_vino),'[]') AS composicion,
        COALESCE((SELECT jsonb_agg(jsonb_build_object('id_maridaje',m.id_maridaje,
          'nombre',m.nombre,'temperatura_servicio',m.temperatura_servicio) ORDER BY m.id_maridaje)
          FROM vino_maridaje vm JOIN maridaje m USING(id_maridaje)
          WHERE vm.codigo_vino=v.codigo_vino),'[]') AS maridajes,
        st.cantidad_total_disponible AS stock_total
        FROM vino v JOIN bodega b ON b.cuit=v.cuit_bodega
        JOIN vw_stock_total_vino st USING(codigo_vino) WHERE v.codigo_vino=%s""", (codigo,)))


def guardar_vino(conn, codigo, pedido, nuevo):
    datos = pedido.model_dump(exclude={"codigo_vino", "composicion"})
    columnas = list(datos)
    if nuevo:
        conn.execute(sql.SQL("INSERT INTO vino ({},codigo_vino) VALUES ({},%s)").format(
            sql.SQL(",").join(map(sql.Identifier, columnas)),
            sql.SQL(",").join(sql.Placeholder() for _ in columnas)), (*datos.values(), codigo))
    else:
        uno(conn.execute("SELECT codigo_vino FROM vino WHERE codigo_vino=%s FOR UPDATE", (codigo,)))
        conn.execute(sql.SQL("UPDATE vino SET {} WHERE codigo_vino=%s").format(
            sql.SQL(",").join(sql.SQL("{}=%s").format(sql.Identifier(k)) for k in columnas)),
            (*datos.values(), codigo))
        conn.execute("DELETE FROM composicion_vino_cepa WHERE codigo_vino=%s", (codigo,))
    for c in pedido.composicion:
        conn.execute("INSERT INTO composicion_vino_cepa VALUES (%s,%s,%s)",
                     (codigo, c.id_cepa, c.porcentaje_corte))
    return vino(conn, codigo)


def borrar_vino(conn, codigo):
    fila = conn.execute("SELECT fn_eliminar_vino_sin_movimientos(%s) AS eliminado", (codigo,)).fetchone()
    if not fila["eliminado"]:
        raise HTTPException(404, "Recurso inexistente")


CLIENTE_SELECT = """SELECT c.*,d.zona_cobertura,d.numero_habilitacion,e.pais_destino
    FROM cliente c LEFT JOIN distribuidor d USING(id_cliente)
    LEFT JOIN exportador e USING(id_cliente)"""


def clientes(conn, limite, offset):
    return conn.execute(CLIENTE_SELECT + " ORDER BY c.id_cliente LIMIT %s OFFSET %s", (limite, offset)).fetchall()


def catalogos(conn):
    return {
        "salas": conn.execute("SELECT id_sala,calle,numero,codigo_postal FROM sala_venta ORDER BY id_sala").fetchall(),
        "cepas": conn.execute("SELECT id_cepa,nombre,tipo FROM cepa ORDER BY nombre,id_cepa").fetchall(),
        "bodegas": conn.execute("SELECT cuit,razon_social FROM bodega ORDER BY razon_social,cuit").fetchall(),
    }


def cliente(conn, identificador):
    return uno(conn.execute(CLIENTE_SELECT + " WHERE c.id_cliente=%s", (identificador,)))


def guardar_cliente(conn, identificador, pedido, nuevo):
    datos = pedido.model_dump(exclude={"id_cliente", "zona_cobertura", "numero_habilitacion", "pais_destino"})
    columnas = list(datos)
    if nuevo:
        conn.execute(sql.SQL("INSERT INTO cliente ({},id_cliente) VALUES ({},%s)").format(
            sql.SQL(",").join(map(sql.Identifier, columnas)),
            sql.SQL(",").join(sql.Placeholder() for _ in columnas)), (*datos.values(), identificador))
    else:
        uno(conn.execute("SELECT id_cliente FROM cliente WHERE id_cliente=%s FOR UPDATE", (identificador,)))
        # El cambio de subtipo y el supertipo se validan juntos al COMMIT.
        for tabla in ("socio", "distribuidor", "exportador"):
            if tabla == pedido.tipo_cliente:
                continue
            conn.execute(sql.SQL("DELETE FROM {} WHERE id_cliente=%s").format(sql.Identifier(tabla)), (identificador,))
        conn.execute(sql.SQL("UPDATE cliente SET {} WHERE id_cliente=%s").format(
            sql.SQL(",").join(sql.SQL("{}=%s").format(sql.Identifier(k)) for k in columnas)),
            (*datos.values(), identificador))
    if pedido.tipo_cliente == "socio":
        conn.execute("INSERT INTO socio VALUES (%s) ON CONFLICT (id_cliente) DO NOTHING", (identificador,))
    elif pedido.tipo_cliente == "distribuidor":
        conn.execute("""INSERT INTO distribuidor VALUES (%s,%s,%s) ON CONFLICT (id_cliente)
            DO UPDATE SET zona_cobertura=EXCLUDED.zona_cobertura,numero_habilitacion=EXCLUDED.numero_habilitacion""",
                     (identificador, pedido.zona_cobertura, pedido.numero_habilitacion))
    else:
        conn.execute("INSERT INTO exportador VALUES (%s,%s) ON CONFLICT (id_cliente) DO UPDATE SET pais_destino=EXCLUDED.pais_destino", (identificador, pedido.pais_destino))
    return cliente(conn, identificador)


def borrar_cliente(conn, identificador):
    uno(conn.execute("DELETE FROM cliente WHERE id_cliente=%s RETURNING id_cliente", (identificador,)))


def comprobante(conn, numero):
    cabecera = uno(conn.execute("SELECT * FROM comprobante WHERE numero_comprobante=%s", (numero,)))
    cabecera["renglones"] = conn.execute("SELECT * FROM comprobante_vino WHERE numero_comprobante=%s ORDER BY codigo_vino", (numero,)).fetchall()
    return cabecera


def crear_comprobante(conn, pedido):
    conn.execute("INSERT INTO comprobante(numero_comprobante,fecha,id_cliente,id_sala) VALUES (%s,%s,%s,%s)",
                 (pedido.numero_comprobante, pedido.fecha, pedido.id_cliente, pedido.id_sala))
    for r in sorted(pedido.renglones, key=lambda r: r.codigo_vino):
        # Escalar: vino inexistente produce NULL y falla; no omite el pedido.
        # Precio consultado en PostgreSQL, nunca confiado al frontend.
        conn.execute("""INSERT INTO comprobante_vino(numero_comprobante,codigo_vino,cantidad,precio)
            VALUES (%s,%s,%s,(SELECT precio FROM vino WHERE codigo_vino=%s FOR SHARE))""",
            (pedido.numero_comprobante, r.codigo_vino, r.cantidad, r.codigo_vino))
    return comprobante(conn, pedido.numero_comprobante)


# Identificadores cerrados: nunca se recibe el nombre de una tabla desde HTTP.
DOCUMENTOS = {
    "transferencias": ("transferencia", "numero_solicitud", "transferencia_vino", "sp_procesar_transferencia"),
    "ingresos": ("ingreso", "codigo_ingreso", "ingreso_vino", "sp_procesar_ingreso"),
}


def crear_documento(conn, recurso, pedido):
    tabla, clave, _, _ = DOCUMENTOS[recurso]
    datos = pedido.model_dump()
    return uno(conn.execute(sql.SQL("INSERT INTO {} ({}) VALUES ({}) RETURNING *").format(
        sql.Identifier(tabla), sql.SQL(",").join(map(sql.Identifier, datos)),
        sql.SQL(",").join(sql.Placeholder() for _ in datos)), tuple(datos.values())))


def agregar_renglon(conn, recurso, numero, pedido):
    tabla, clave, detalle, _ = DOCUMENTOS[recurso]
    uno(conn.execute(sql.SQL("SELECT {} FROM {} WHERE {}=%s FOR UPDATE").format(
        sql.Identifier(clave), sql.Identifier(tabla), sql.Identifier(clave)), (numero,)))
    return uno(conn.execute(sql.SQL("INSERT INTO {} ({},codigo_vino,cantidad_botellas) VALUES (%s,%s,%s) RETURNING *").format(
        sql.Identifier(detalle), sql.Identifier(clave)), (numero, pedido.codigo_vino, pedido.cantidad_botellas)))


def cambiar_estado(conn, recurso, numero, procesar):
    tabla, clave, _, procedimiento = DOCUMENTOS[recurso]
    uno(conn.execute(sql.SQL("SELECT {} FROM {} WHERE {}=%s FOR UPDATE").format(
        sql.Identifier(clave), sql.Identifier(tabla), sql.Identifier(clave)), (numero,)))
    if procesar:
        conn.execute(sql.SQL("CALL {}(%s)").format(sql.Identifier(procedimiento)), (numero,))
    else:
        conn.execute(sql.SQL("UPDATE {} SET estado='terminado' WHERE {}=%s").format(
            sql.Identifier(tabla), sql.Identifier(clave)), (numero,))
    return uno(conn.execute(sql.SQL("SELECT * FROM {} WHERE {}=%s").format(
        sql.Identifier(tabla), sql.Identifier(clave)), (numero,)))


def top_vinos(conn):
    return conn.execute("""SELECT v.codigo_vino,v.nombre_comercial,sum(cv.cantidad) AS botellas
        FROM vino v JOIN comprobante_vino cv USING(codigo_vino)
        GROUP BY v.codigo_vino ORDER BY botellas DESC,v.codigo_vino LIMIT 10""").fetchall()


def ventas_sala(conn):
    return conn.execute("""SELECT s.id_sala,COALESCE(sum(c.total),0) AS total_ventas FROM sala_venta s
        LEFT JOIN comprobante c ON c.id_sala=s.id_sala
        AND c.fecha>=CURRENT_DATE-INTERVAL '3 months' AND c.fecha<CURRENT_DATE+1
        GROUP BY s.id_sala ORDER BY total_ventas DESC,s.id_sala""").fetchall()


def sin_stock(conn, sala):
    return conn.execute("""SELECT v.codigo_vino,v.nombre_comercial,d.cantidad_botellas_disponibles
        FROM vino v JOIN stock_deposito d USING(codigo_vino)
        LEFT JOIN stock_sala s ON s.codigo_vino=v.codigo_vino AND s.id_sala=%s
        WHERE COALESCE(s.cantidad_stock,0)=0 AND d.cantidad_botellas_disponibles>0
        ORDER BY v.codigo_vino""", (sala,)).fetchall()


def transportista_activo(conn):
    return conn.execute("""SELECT t.codigo_transporte,t.razon_social,count(i.codigo_ingreso) AS ingresos
        FROM transportista t JOIN ingreso i USING(codigo_transporte)
        WHERE i.fecha>=CURRENT_DATE-INTERVAL '1 month' AND i.fecha<CURRENT_DATE+1
        GROUP BY t.codigo_transporte ORDER BY ingresos DESC,t.codigo_transporte LIMIT 1""").fetchone()


def trazabilidad(conn, codigo):
    # La composición referencia cepas, no lotes consumidos por vino. Mostrar
    # únicamente relaciones comprobables, sin inventar trazabilidad de producción.
    ficha = vino(conn, codigo)
    ficha["ingresos"] = conn.execute("""SELECT i.*,iv.cantidad_botellas FROM ingreso i
        JOIN ingreso_vino iv USING(codigo_ingreso) WHERE iv.codigo_vino=%s ORDER BY i.fecha,i.codigo_ingreso""", (codigo,)).fetchall()
    ficha["transferencias"] = conn.execute("""SELECT t.*,tv.cantidad_botellas FROM transferencia t
        JOIN transferencia_vino tv USING(numero_solicitud) WHERE tv.codigo_vino=%s
        ORDER BY t.fecha_confeccion,t.numero_solicitud""", (codigo,)).fetchall()
    return ficha
