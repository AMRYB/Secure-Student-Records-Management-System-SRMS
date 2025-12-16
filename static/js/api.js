export async function apiFetch(path, { method = "GET", body = null } = {}) {
  const opts = {
    method,
    headers: { "Content-Type": "application/json" },
    credentials: "include",
  };

  if (body !== null) opts.body = JSON.stringify(body);

  const res = await fetch(path, opts);

  let data = null;
  try {
    data = await res.json();
  } catch {
    data = { ok: false, error: "Non-JSON response" };
  }

  if (!res.ok) {
    const msg = data?.error || `HTTP ${res.status}`;
    throw new Error(msg);
  }

  return data;
}
