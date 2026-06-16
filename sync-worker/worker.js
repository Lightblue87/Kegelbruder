// Cloudflare Worker backend for Kegel Brueder PWA snapshot sync.
//
// Required bindings:
// - KV namespace binding: KBG_SYNC
// - Secret: SYNC_SECRET
//
// API:
// GET /sync/:clubId
// GET /sync/:clubId?includeDb=1
// PUT /sync/:clubId

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,PUT,OPTIONS",
  "Access-Control-Allow-Headers": "Authorization,Content-Type",
  "Access-Control-Max-Age": "86400",
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

function unauthorized() {
  return json({ message: "Nicht autorisiert." }, 401);
}

function getBearer(request) {
  const header = request.headers.get("Authorization") || "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match ? match[1] : "";
}

async function verifyAuth(request, env) {
  const expected = env.SYNC_SECRET || "";
  const actual = getBearer(request);
  return expected.length > 0 && actual === expected;
}

function route(url) {
  const parts = url.pathname.split("/").filter(Boolean);
  if (parts.length === 2 && parts[0] === "sync") return decodeURIComponent(parts[1]);
  return null;
}

function publicRecord(record, includeDb) {
  if (!record) return { exists: false, revision: null };
  const result = {
    exists: true,
    revision: record.revision,
    updatedAt: record.updatedAt,
    deviceId: record.deviceId,
    deviceName: record.deviceName,
    size: record.size || 0,
  };
  if (includeDb) result.dbBase64 = record.dbBase64;
  return result;
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });

    const url = new URL(request.url);
    const clubId = route(url);
    if (!clubId) return json({ message: "Nicht gefunden." }, 404);
    if (!(await verifyAuth(request, env))) return unauthorized();

    const key = `club:${clubId}`;

    if (request.method === "GET") {
      const record = await env.KBG_SYNC.get(key, "json");
      return json(publicRecord(record, url.searchParams.get("includeDb") === "1"));
    }

    if (request.method === "PUT") {
      const body = await request.json().catch(() => null);
      if (!body || typeof body.dbBase64 !== "string") {
        return json({ message: "Ungültiger Upload." }, 400);
      }

      const current = await env.KBG_SYNC.get(key, "json");
      const baseRevision = body.baseRevision || null;
      if (current && baseRevision !== current.revision) {
        return json(
          {
            message: "Remote-Stand ist neuer. Erst herunterladen oder bewusst neu hochladen.",
            revision: current.revision,
            updatedAt: current.updatedAt,
            deviceId: current.deviceId,
            deviceName: current.deviceName,
          },
          409
        );
      }

      const now = new Date().toISOString();
      const revision = crypto.randomUUID();
      const record = {
        revision,
        updatedAt: now,
        deviceId: String(body.deviceId || ""),
        deviceName: String(body.deviceName || "Unbekanntes Gerät"),
        size: body.dbBase64.length,
        dbBase64: body.dbBase64,
      };
      await env.KBG_SYNC.put(key, JSON.stringify(record));
      return json(publicRecord(record, false));
    }

    return json({ message: "Methode nicht erlaubt." }, 405);
  },
};
