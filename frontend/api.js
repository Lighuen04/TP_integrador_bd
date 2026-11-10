// Se puede configurar una URL pública antes de cargar este módulo, sin secretos.
const base = (window.API_BASE_URL ?? document.querySelector('meta[name="api-base"]').content).replace(/\/$/, "");

export async function request(path, { method = "GET", data, params, signal } = {}) {
  const url = new URL(base + path, location.origin);
  for (const [key, value] of Object.entries(params ?? {})) {
    if (value !== "" && value != null) url.searchParams.set(key, value);
  }
  let response;
  try {
    response = await fetch(url, {
      method, signal,
      headers: data === undefined ? { Accept: "application/json" } : { Accept: "application/json", "Content-Type": "application/json" },
      body: data === undefined ? undefined : JSON.stringify(data),
    });
  } catch (error) {
    if (error.name === "AbortError") throw error;
    throw new Error("No se pudo conectar con la API. Verificá la conexión e intentá nuevamente.");
  }
  if (response.status === 204) return null;
  const result = await response.json().catch(() => undefined);
  if (!response.ok) {
    const error = new Error(result?.detalle ?? ([502, 503, 504].includes(response.status)
      ? "El servicio no está disponible temporalmente. Intentá nuevamente."
      : `No se pudo completar la operación (HTTP ${response.status}).`));
    error.status = response.status;
    error.sqlstate = result?.sqlstate;
    throw error;
  }
  if (result === undefined) throw new Error("La API devolvió una respuesta que no se pudo interpretar.");
  return result;
}
