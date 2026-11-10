import { request } from "./api.js";

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const money = value => new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS" }).format(value);
const state = { catalogs: null, offset: 0, clientOffset: 0, clientHasNext: false, clientsLoaded: false, clientSequence: 0, edit: null, detail: null, transfer: null, catalogSequence: 0 };

function node(tag, text, className) {
  const element = document.createElement(tag);
  if (text !== undefined) element.textContent = text;
  if (className) element.className = className;
  return element;
}
function message(id, text, type = "success") {
  const target = $(id);
  target.textContent = text;
  target.dataset.type = type;
  target.hidden = !text;
}
async function busy(target, messageId, action) {
  if (target.dataset.busy === "true") return;
  target.dataset.busy = "true";
  const controls = $$('button,input,select', target).concat(target.matches("button") ? [target] : []);
  const previous = controls.map(control => control.disabled);
  controls.forEach(control => { control.disabled = true; });
  target.setAttribute("aria-busy", "true");
  message(messageId, "Procesando…", "loading");
  try { await action(); }
  catch (error) { if (error.name !== "AbortError") message(messageId, error.message, "error"); }
  finally {
    controls.forEach((control, i) => { control.disabled = previous[i]; });
    target.dataset.busy = "false";
    target.removeAttribute("aria-busy");
    if (target.classList.contains("client-pagination")) {
      $("#clientes-anterior").disabled = state.clientOffset === 0;
      $("#clientes-siguiente").disabled = !state.clientHasNext;
    }
    if (state.transfer) updateTransfer();
  }
}
function table(headers, rows) {
  if (!rows.length) return node("p", "No hay resultados para esta consulta.", "empty");
  const wrapper = node("div", undefined, "table-scroll"), result = node("table");
  const head = node("thead"), hr = node("tr"), body = node("tbody");
  headers.forEach(h => hr.append(node("th", h)));
  head.append(hr);
  rows.forEach(row => { const tr = node("tr"); row.forEach(value => tr.append(node("td", value ?? "—"))); body.append(tr); });
  result.append(head, body); wrapper.append(result); return wrapper;
}
function options(select, records, key, label, placeholder) {
  const previous = select.value;
  select.replaceChildren(new Option(placeholder, ""));
  records.forEach(record => select.add(new Option(label(record), record[key])));
  select.value = previous;
}
async function catalogs() {
  state.catalogs = await request("/catalogos");
  $$('[data-cepas]').forEach(select => options(select, state.catalogs.cepas, "id_cepa", r => r.nombre, select.options[0]?.text ?? "Seleccionar cepa"));
  $$('[data-bodegas]').forEach(select => options(select, state.catalogs.bodegas, "cuit", r => r.razon_social, select.options[0]?.text ?? "Seleccionar bodega"));
  $$('[data-salas]').forEach(select => options(select, state.catalogs.salas, "id_sala", r => `Sala ${r.id_sala} · ${r.calle} ${r.numero}`, select.options[0]?.text ?? "Seleccionar sala"));
}
async function health() {
  const button = $("#salud");
  button.disabled = true;
  $("#salud-texto").textContent = "Comprobando conexión…";
  try {
    await request("/salud");
    button.dataset.estado = "ok"; $("#salud-texto").textContent = "Sistema conectado";
    if (!state.catalogs) await catalogs();
    if (!state.clientsLoaded) await clients();
    message("#aviso-global", "");
  } catch (error) {
    button.dataset.estado = "error"; $("#salud-texto").textContent = "Sin conexión · reintentar";
    message("#aviso-global", error.message, "error");
  } finally { button.disabled = false; }
}
async function catalog() {
  const sequence = ++state.catalogSequence;
  const params = Object.fromEntries(new FormData($("#filtros")));
  params.limite = Number($("#limite").value); params.offset = state.offset;
  $("#anterior").disabled = true; $("#siguiente").disabled = true;
  $("#vinos-body").replaceChildren();
  message("#catalogo-mensaje", "Cargando etiquetas…", "loading");
  try {
    const rows = await request("/vinos", { params });
    if (sequence !== state.catalogSequence) return;
    rows.forEach(v => {
      const tr = node("tr"), td = node("td"), cell = node("div", undefined, "wine-cell");
      const symbol = node("span", "♧", "wine-symbol"); symbol.setAttribute("aria-hidden", "true");
      const name = node("div"); name.append(node("span", v.nombre_comercial, "wine-name"), node("span", v.codigo_vino, "wine-code")); cell.append(symbol, name); td.append(cell); tr.append(td);
      const type = node("span", v.tipo, "type-tag"); type.dataset.tipo = v.tipo; const typeCell = node("td"); typeCell.append(type); tr.append(typeCell);
      [v.anada, `${v.presentacion_ml} ml`, money(v.precio)].forEach(value => tr.append(node("td", value)));
      const actions = node("td"), buttons = node("div", undefined, "row-actions");
      const detail = node("button", "Ver detalle", "text-button"), edit = node("button", "Editar");
      detail.type = edit.type = "button";
      detail.addEventListener("click", () => busy(detail, "#catalogo-mensaje", () => showDetail(v.codigo_vino)));
      edit.addEventListener("click", () => busy(edit, "#catalogo-mensaje", () => editWine(v.codigo_vino)));
      buttons.append(detail, edit); actions.append(buttons); tr.append(actions); $("#vinos-body").append(tr);
    });
    $("#vinos-sugeridos").replaceChildren(...rows.map(v => new Option(`${v.nombre_comercial} · ${money(v.precio)}`, v.codigo_vino)));
    message("#catalogo-mensaje", rows.length ? "" : "No hay vinos que coincidan con los filtros.");
    $("#pagina-texto").textContent = rows.length ? `Mostrando ${state.offset + 1}–${state.offset + rows.length} · Página ${Math.floor(state.offset / params.limite) + 1}` : "Sin resultados";
    $("#anterior").disabled = state.offset === 0;
    $("#siguiente").disabled = rows.length < params.limite;
  } catch (error) { if (sequence === state.catalogSequence) { message("#catalogo-mensaje", error.message, "error"); $("#pagina-texto").textContent = "No se pudo cargar el catálogo"; } }
}
function definition(records) {
  const dl = node("dl", undefined, "detail-grid");
  records.forEach(([title, value]) => { const group = node("div"); group.append(node("dt", title), node("dd", value)); dl.append(group); });
  return dl;
}
async function showDetail(code) {
  const v = await request(`/vinos/${encodeURIComponent(code)}`); state.detail = v;
  const title = node("h2", v.nombre_comercial); title.id = "detalle-titulo";
  $("#detalle-contenido").replaceChildren(title, node("p", v.codigo_vino, "wine-code"), definition([
    ["Tipo / añada", `${v.tipo} · ${v.anada}`], ["Bodega", v.bodega], ["Presentación", `${v.presentacion_ml} ml`], ["Graduación", `${v.graduacion_alcoholica} %`], ["Precio", money(v.precio)], ["Stock total", `${v.stock_total} botellas`],
  ]), node("h3", "Composición"), table(["Cepa", "Porcentaje"], v.composicion.map(c => [c.cepa, `${c.porcentaje_corte} %`])), node("h3", "Maridajes"),
  v.maridajes.length ? table(["Maridaje", "Temperatura"], v.maridajes.map(m => [m.nombre, `${m.temperatura_servicio} °C`])) : node("p", "Sin maridajes registrados.", "muted"));
  message("#catalogo-mensaje", ""); $("#detalle-dialog").showModal();
}
function compositionRow(c = {}) {
  const row = node("div", undefined, "line-row"), label = node("label", "Cepa"), select = node("select"); select.required = true; select.name = "cepa"; select.dataset.cepas = "";
  options(select, state.catalogs?.cepas ?? [], "id_cepa", r => r.nombre, "Seleccionar cepa"); select.value = c.id_cepa ?? ""; label.append(select);
  const pctLabel = node("label", "Porcentaje (%)"), pct = node("input"); pct.type = "number"; pct.step = ".01"; pct.required = true; pct.name = "porcentaje"; pct.value = c.porcentaje_corte ?? ""; pct.addEventListener("input", sumComposition); pctLabel.append(pct);
  const remove = node("button", "Quitar", "text-button"); remove.type = "button"; remove.addEventListener("click", () => { row.remove(); sumComposition(); });
  row.append(label, pctLabel, remove); $("#composicion").append(row); sumComposition();
}
function sumComposition() { $("#suma-corte").textContent = `${$$("#composicion input").reduce((sum, input) => sum + Number(input.value || 0), 0).toLocaleString("es-AR")} %`; }
function resetWine() {
  state.edit = null; $("#vino-form").reset(); $("#vino-form [name=codigo_vino]").readOnly = false;
  $("#modo-vino").textContent = "Nueva etiqueta"; $("#eliminar-vino").hidden = true; $("#composicion").replaceChildren(); compositionRow(); message("#vino-mensaje", "");
}
async function editWine(code) {
  const v = await request(`/vinos/${encodeURIComponent(code)}`); state.edit = code;
  const form = $("#vino-form");
  for (const input of $$('[name]', form)) if (v[input.name] != null) input.value = v[input.name];
  $("[name=codigo_vino]", form).readOnly = true;
  $("#modo-vino").textContent = `Editar ${code}`; $("#eliminar-vino").hidden = false;
  $("#composicion").replaceChildren(); v.composicion.forEach(compositionRow); message("#vino-mensaje", "");
  $("#detalle-dialog").close(); location.hash = "gestion";
}
async function clients() {
  const sequence = ++state.clientSequence;
  const rows = await request("/clientes", { params: { limite: 20, offset: state.clientOffset } });
  if (sequence !== state.clientSequence) return;
  state.clientsLoaded = true;
  state.clientHasNext = rows.length === 20;
  options($("#venta-cliente"), rows, "id_cliente", c => `${c.id_cliente} · ${c.nombre} ${c.apellido ?? ""} · ${c.tipo_cliente}`, "Seleccionar cliente");
  $("#clientes-pagina").textContent = `Clientes · Página ${Math.floor(state.clientOffset / 20) + 1}`;
  $("#clientes-anterior").disabled = state.clientOffset === 0; $("#clientes-siguiente").disabled = rows.length < 20;
}
function saleRow(code = "", quantity = "1") {
  const row = node("div", undefined, "line-row"), wine = node("label", "Código de vino"), input = node("input"); input.name = "codigo_vino"; input.required = true; input.maxLength = 40; input.value = code; input.setAttribute("list", "vinos-sugeridos"); wine.append(input);
  const qty = node("label", "Botellas"), amount = node("input"); amount.name = "cantidad"; amount.type = "number"; amount.step = "1"; amount.required = true; amount.value = quantity; qty.append(amount);
  const remove = node("button", "Quitar", "text-button"); remove.type = "button"; remove.addEventListener("click", () => row.remove()); row.append(wine, qty, remove); $("#venta-lineas").append(row);
}
function updateTransfer() {
  const transfer = state.transfer; if (!transfer) return;
  $("#transferencia-detalle").hidden = false; $("#transferencia-numero").textContent = transfer.numero_solicitud;
  $("#transferencia-estado").textContent = transfer.estado; $("#transferencia-sala").textContent = `Destino: sala ${transfer.id_sala} · Fecha: ${transfer.fecha_confeccion}`;
  const inProgress = transfer.estado === "en_confeccion";
  $$("#transferencia-form input,#transferencia-form select,#transferencia-form button").forEach(c => { c.disabled = true; });
  $$("#transferencia-renglon input,#transferencia-renglon button").forEach(c => { c.disabled = !inProgress; });
  $("#terminar-transferencia").disabled = !inProgress; $("#procesar-transferencia").disabled = transfer.estado !== "terminado";
  $$(".steps li").forEach(li => { if (li.dataset.estado === transfer.estado) li.setAttribute("aria-current", "step"); else li.removeAttribute("aria-current"); });
  // Las operaciones de una misma solicitud se serializan también en pantalla.
  if ($$("[data-transfer-busy=true]").length) $$("#transferencia-detalle button,#nueva-transferencia").forEach(c => { c.disabled = true; });
}
async function transferAction(target, action) {
  if ($$("[data-transfer-busy=true]").length) return;
  target.dataset.transferBusy = "true"; $("#nueva-transferencia").disabled = true; updateTransfer();
  await busy(target, "#transferencia-mensaje", action);
  delete target.dataset.transferBusy; $("#nueva-transferencia").disabled = false; updateTransfer();
}
async function noStock() {
  const sala = $("#reporte-sala").value;
  if (!sala) { $("#sin-stock").replaceChildren(node("p", "Seleccioná una sala para consultar.", "empty")); return; }
  $("#sin-stock").replaceChildren(node("p", "Consultando disponibilidad…", "muted"));
  try { const rows = await request("/reportes/vinos-sin-stock", { params: { sala } }); if (sala !== $("#reporte-sala").value) return; $("#sin-stock").replaceChildren(table(["Vino", "Código", "En depósito"], rows.map(r => [r.nombre_comercial, r.codigo_vino, r.cantidad_botellas_disponibles]))); }
  catch (error) { $("#sin-stock").replaceChildren(node("p", error.message, "notice")); }
}
async function reports() {
  await busy($("#actualizar-reportes"), "#reportes-mensaje", async () => {
    ["#grafico-ventas", "#ventas-tabla", "#top-vinos", "#transportista"].forEach(id => $(id).replaceChildren());
    const [top, sales, carrier] = await Promise.all([request("/reportes/top-vinos"), request("/reportes/ventas-por-sala"), request("/reportes/transportista-activo")]);
    $("#top-vinos").replaceChildren(table(["Vino", "Código", "Botellas"], top.map(r => [r.nombre_comercial, r.codigo_vino, r.botellas])));
    $("#ventas-tabla").replaceChildren(table(["Sala", "Ventas"], sales.map(r => [r.id_sala, money(r.total_ventas)])));
    const max = Math.max(0, ...sales.map(r => Number(r.total_ventas)));
    sales.forEach(s => { const row = node("div", undefined, "bar-row"), track = node("div", undefined, "bar-track"), bar = node("div", undefined, "bar"); bar.style.width = `${max ? Math.max(0, Number(s.total_ventas)) / max * 100 : 0}%`; track.append(bar); row.append(node("span", `Sala ${s.id_sala}`), track, node("strong", money(s.total_ventas))); $("#grafico-ventas").append(row); });
    if (!sales.length) $("#grafico-ventas").append(node("p", "Sin ventas para mostrar.", "empty"));
    $("#transportista").replaceChildren(...(carrier ? [node("p", carrier.razon_social, "carrier-name"), node("p", carrier.codigo_transporte, "wine-code"), node("p", carrier.ingresos, "carrier-count"), node("p", "ingresos asociados en el último mes", "muted")] : [node("p", "No hubo actividad de transportistas en el último mes.", "empty")]));
    await noStock(); message("#reportes-mensaje", "");
  });
}
function navigate() {
  const id = location.hash.slice(1) || "catalogo", screen = ["catalogo", "gestion", "venta", "transferencias", "reportes"].includes(id) ? id : "catalogo";
  $$(".screen").forEach(section => { section.hidden = section.id !== screen; });
  $$("nav a").forEach(a => { if (a.hash === `#${screen}`) a.setAttribute("aria-current", "page"); else a.removeAttribute("aria-current"); });
  document.title = `${$("h1", $("#" + screen)).textContent} · Bodegas del Atuel`;
  if (screen === "reportes") reports();
}

$("#filtros").addEventListener("submit", event => { event.preventDefault(); state.offset = 0; catalog(); });
$("#limpiar-filtros").addEventListener("click", () => { $("#filtros").reset(); state.offset = 0; catalog(); });
$("#limite").addEventListener("change", () => { state.offset = 0; catalog(); });
$("#anterior").addEventListener("click", () => { state.offset = Math.max(0, state.offset - Number($("#limite").value)); catalog(); });
$("#siguiente").addEventListener("click", () => { state.offset += Number($("#limite").value); catalog(); });
$("#buscar-codigo").addEventListener("submit", event => { event.preventDefault(); const code = $("#codigo-busqueda").value; busy(event.currentTarget, "#catalogo-mensaje", () => showDetail(code)); });
$("#cerrar-detalle").addEventListener("click", () => $("#detalle-dialog").close());
$("#detalle-editar").addEventListener("click", event => busy(event.currentTarget, "#catalogo-mensaje", () => editWine(state.detail.codigo_vino)));
$("#detalle-vender").addEventListener("click", () => { $$("#venta-lineas .line-row").filter(row => !$("[name=codigo_vino]", row).value).forEach(row => row.remove()); saleRow(state.detail.codigo_vino); $("#detalle-dialog").close(); location.hash = "venta"; });
for (const id of ["#nuevo-vino", "#catalogo-nuevo"]) $(id).addEventListener("click", event => { if ($("#vino-form").dataset.busy === "true") { event.preventDefault(); return; } resetWine(); });
$("#agregar-cepa").addEventListener("click", () => compositionRow());
$("#vino-form").addEventListener("submit", event => {
  event.preventDefault(); const form = event.currentTarget, data = Object.fromEntries(new FormData(form));
  ["anada", "presentacion_ml"].forEach(key => { data[key] = Number(data[key]); });
  delete data.cepa; delete data.porcentaje;
  data.composicion = $$("#composicion .line-row").map(row => ({ id_cepa: Number($("select", row).value), porcentaje_corte: $("input", row).value }));
  const code = state.edit ?? data.codigo_vino, editing = state.edit !== null; if (editing) delete data.codigo_vino;
  busy(form, "#vino-mensaje", async () => { await request(editing ? `/vinos/${encodeURIComponent(code)}` : "/vinos", { method: editing ? "PUT" : "POST", data }); state.edit = code; $("[name=codigo_vino]", form).readOnly = true; $("#eliminar-vino").hidden = false; $("#modo-vino").textContent = `Editar ${code}`; message("#vino-mensaje", `Vino ${code} guardado correctamente.`); await catalog(); });
});
$("#eliminar-vino").addEventListener("click", () => $("#baja-dialog").showModal());
$("#cancelar-baja").addEventListener("click", () => $("#baja-dialog").close());
$("#confirmar-baja").addEventListener("click", event => { $("#baja-dialog").close(); busy($("#vino-form"), "#vino-mensaje", async () => { await request(`/vinos/${encodeURIComponent(state.edit)}`, { method: "DELETE" }); resetWine(); message("#vino-mensaje", "Vino eliminado correctamente."); await catalog(); }); });
$("#agregar-venta").addEventListener("click", () => saleRow());
$("#venta-form").addEventListener("submit", event => {
  event.preventDefault(); const form = event.currentTarget, data = Object.fromEntries(new FormData(form));
  delete data.codigo_vino; delete data.cantidad;
  data.id_cliente = Number(data.id_cliente); data.id_sala = Number(data.id_sala);
  data.renglones = $$("#venta-lineas .line-row").map(row => ({ codigo_vino: $("[name=codigo_vino]", row).value, cantidad: Number($("[name=cantidad]", row).value) }));
  $("#venta-resultado").hidden = true;
  busy(form, "#venta-mensaje", async () => {
    const receipt = await request("/comprobantes", { method: "POST", data });
    const result = $("#venta-resultado"); result.hidden = false;
    result.replaceChildren(node("p", "VENTA CONFIRMADA", "eyebrow"), node("h2", `Comprobante ${receipt.numero_comprobante}`), definition([["Cliente", receipt.id_cliente], ["Sala", receipt.id_sala], ["Fecha", receipt.fecha], ["Descuento aplicado", `${receipt.descuento_aplicado} %`]]), table(["Vino", "Botellas", "Precio histórico"], receipt.renglones.map(r => [r.codigo_vino, r.cantidad, money(r.precio)])), node("p", money(receipt.total), "receipt-total"));
    message("#venta-mensaje", "Venta realizada correctamente. El comprobante ya está guardado.");
    form.reset(); $("#venta-lineas").replaceChildren(); saleRow(); await catalog();
  });
});
for (const [id, step] of [["#clientes-anterior", -20], ["#clientes-siguiente", 20]]) $(id).addEventListener("click", () => busy($(".client-pagination"), "#venta-mensaje", async () => { const previous = state.clientOffset; state.clientOffset = Math.max(0, state.clientOffset + step); try { await clients(); } catch (error) { state.clientOffset = previous; throw error; } message("#venta-mensaje", ""); }));
$("#transferencia-form").addEventListener("submit", event => {
  event.preventDefault(); const data = Object.fromEntries(new FormData(event.currentTarget)); data.id_sala = Number(data.id_sala);
  transferAction(event.currentTarget, async () => { state.transfer = await request("/transferencias", { method: "POST", data }); updateTransfer(); message("#transferencia-mensaje", "Transferencia creada. Agregá sus renglones."); });
});
$("#transferencia-renglon").addEventListener("submit", event => {
  event.preventDefault(); const form = event.currentTarget, data = Object.fromEntries(new FormData(form)); data.cantidad_botellas = Number(data.cantidad_botellas);
  transferAction(form, async () => { const r = await request(`/transferencias/${encodeURIComponent(state.transfer.numero_solicitud)}/renglones`, { method: "POST", data }); $("#transferencia-lineas").append(node("p", `${r.codigo_vino} · ${r.cantidad_botellas} botellas`, "notice")); form.reset(); message("#transferencia-mensaje", "Renglón guardado correctamente."); });
});
for (const [id, action] of [["#terminar-transferencia", "terminar"], ["#procesar-transferencia", "procesar"]]) $(id).addEventListener("click", event => transferAction(event.currentTarget, async () => { state.transfer = await request(`/transferencias/${encodeURIComponent(state.transfer.numero_solicitud)}/${action}`, { method: "POST" }); message("#transferencia-mensaje", `Transferencia confirmada en estado ${state.transfer.estado}.`); }));
$("#nueva-transferencia").addEventListener("click", () => { state.transfer = null; $("#transferencia-form").reset(); $$("#transferencia-form input,#transferencia-form select,#transferencia-form button").forEach(c => { c.disabled = false; }); $("#transferencia-detalle").hidden = true; $("#transferencia-lineas").replaceChildren(); message("#transferencia-mensaje", ""); });
$("#actualizar-reportes").addEventListener("click", reports); $("#reporte-sala").addEventListener("change", noStock);
$("#salud").addEventListener("click", async () => { await health(); await catalog(); });
window.addEventListener("hashchange", navigate);
resetWine(); saleRow(); navigate(); health(); catalog();
