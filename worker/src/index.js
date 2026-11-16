const json = (value, status = 200) => new Response(JSON.stringify(value), {
  status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" }
});
const fail = (status, code) => json({ ok: false, error: code }, status);
const platforms = new Set(["ios", "android"]);
const now = () => Math.floor(Date.now() / 1000);
const matches = (v) => typeof v === "string" && v.length >= 8 && v.length <= 128;
async function body(request) {
  try {
    const raw = await request.text();
    return raw.length < 8192 ? JSON.parse(raw) : null;
  } catch { return null; }
}
function makeKey() {
  const bytes = crypto.getRandomValues(new Uint8Array(20));
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  return "ERI-" + Array.from(bytes, x => alphabet[x % alphabet.length]).join("");
}
async function deviceDigest(platform, deviceId, pepper) {
  const input = new TextEncoder().encode(pepper + ":" + platform + ":" + deviceId);
  const hash = await crypto.subtle.digest("SHA-256", input);
  return [...new Uint8Array(hash)].map(x => x.toString(16).padStart(2, "0")).join("");
}
function adminAuthorized(req, env) {
  // Admin key is configured as a Worker secret, never embedded in the IPA.
  const supplied = req.headers.get("x-eri-admin-key") || "";
  return env.ADMIN_KEY && supplied.length >= 32 && supplied === env.ADMIN_KEY;
}
async function admin(request, env, url, parts) {
  if (!adminAuthorized(request, env)) return fail(401, "not_authorized");
  const method = request.method;
  if (url.pathname === "/api/admin/keys" && method === "GET") {
    const platform = url.searchParams.get("platform");
    if (platform && !platforms.has(platform)) return fail(400, "invalid_platform");
    const query = platform
      ? env.DB.prepare("SELECT * FROM device_keys WHERE platform=? ORDER BY created_at DESC LIMIT 500").bind(platform)
      : env.DB.prepare("SELECT * FROM device_keys ORDER BY created_at DESC LIMIT 500");
    const result = await query.all();
    return json({ ok: true, items: result.results.map(row) });
  }
  if (url.pathname === "/api/admin/keys" && method === "POST") {
    const data = await body(request);
    if (!data || !platforms.has(data.platform) || !Number.isInteger(data.days) || data.days < 1 || data.days > 3650) {
      return fail(422, "invalid_request");
    }
    const key = makeKey(), id = crypto.randomUUID(), ts = now();
    await env.DB.prepare("INSERT INTO device_keys (id,key_value,platform,device_id,locked,expires_at,created_at,updated_at) VALUES (?,?,?,?,0,?,?,?)")
      .bind(id, key, data.platform, null, ts + data.days * 86400, ts, ts).run();
    return json({ ok: true, item: { id, key_value: key, platform: data.platform, device_id: null, locked: 0, expires_at: ts + data.days * 86400, created_at: ts, updated_at: ts } }, 201);
  }
  const id = parts[3];
  if (parts[0] !== "api" || parts[1] !== "admin" || parts[2] !== "keys" || !id || parts.length > 5) return fail(404, "not_found");
  const found = await env.DB.prepare("SELECT id,expires_at FROM device_keys WHERE id=?").bind(id).first();
  if (!found) return fail(404, "key_not_found");
  if (parts.length === 4 && method === "DELETE") {
    await env.DB.prepare("DELETE FROM device_keys WHERE id=?").bind(id).run();
    return json({ ok: true });
  }
  const action = parts[4], data = await body(request);
  if (method !== "POST") return fail(405, "method_not_allowed");
  if (action === "extend") {
    if (!data || !Number.isInteger(data.days) || data.days < 1 || data.days > 3650) return fail(422, "invalid_days");
    await env.DB.prepare("UPDATE device_keys SET expires_at=?,updated_at=? WHERE id=?")
      .bind(Math.max(Number(found.expires_at), now()) + data.days * 86400, now(), id).run();
    return json({ ok: true });
  }
  if (action === "lock") {
    if (!data || typeof data.locked !== "boolean") return fail(422, "invalid_locked");
    await env.DB.prepare("UPDATE device_keys SET locked=?,updated_at=? WHERE id=?")
      .bind(data.locked ? 1 : 0, now(), id).run();
    return json({ ok: true });
  }
  // Manually release a key from a device so an administrator can reassign it.
  if (action === "unbind") {
    await env.DB.prepare("UPDATE device_keys SET device_id=NULL,updated_at=? WHERE id=?").bind(now(), id).run();
    return json({ ok: true });
  }
  return fail(404, "not_found");
}
async function verify(request, env) {
  if (!env.DEVICE_PEPPER) return fail(503, "server_not_configured");
  const data = await body(request);
  if (!data || !platforms.has(data.platform) || !matches(data.device_id) ||
      typeof data.key !== "string" || !/^ERI-[A-Z2-9]{20}$/.test(data.key)) return fail(422, "invalid_request");
  const digest = await deviceDigest(data.platform, data.device_id, env.DEVICE_PEPPER);
  const row = await env.DB.prepare("SELECT id,device_id,locked,expires_at FROM device_keys WHERE key_value=? AND platform=?")
    .bind(data.key, data.platform).first();
  if (!row) return fail(403, "invalid_key");
  if (row.locked) return fail(403, "locked");
  if (row.expires_at <= now()) return fail(403, "expired");
  if (row.device_id && row.device_id !== digest) return fail(403, "bound_to_another_device");
  if (!row.device_id) {
    // One binding per platform/device is enforced by the UNIQUE partial index.
    // Conditional UPDATE prevents a different device claiming the same key concurrently.
    try {
      const result = await env.DB.prepare("UPDATE device_keys SET device_id=?,updated_at=? WHERE id=? AND device_id IS NULL")
        .bind(digest, now(), row.id).run();
      if (!result.meta || result.meta.changes !== 1) {
        const current = await env.DB.prepare("SELECT device_id FROM device_keys WHERE id=?").bind(row.id).first();
        if (!current || current.device_id !== digest) return fail(409, "already_claimed");
      }
    } catch { return fail(409, "device_already_registered"); }
  }
  return json({ ok: true, expires_at: row.expires_at });
}
export default {
  async fetch(request, env) {
    try {
      const url = new URL(request.url);
      if (url.pathname === "/api/health" && request.method === "GET") {
        return json({ ok: true, service: "ERI Login Key", database: !!env.DB });
      }
      if (!env.DB) return fail(503, "database_not_configured");
      if (url.pathname === "/api/verify" && request.method === "POST") return await verify(request, env);
      if (url.pathname.startsWith("/api/admin/")) {
        return await admin(request, env, url, url.pathname.split("/").filter(Boolean));
      }
      return fail(404, "not_found");
    } catch (error) {
      // Avoid leaking SQL, secret values or stack traces in API responses.
      return fail(500, "internal_error");
    }
  }
};