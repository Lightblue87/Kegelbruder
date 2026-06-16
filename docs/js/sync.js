// Offline-first snapshot sync for the Kegel Brueder PWA.
//
// The app keeps the authoritative local working copy in IndexedDB/sql.js.
// Sync exchanges full SQLite snapshots with a tiny backend. This is deliberate:
// the club normally has one active scorer device, and full snapshots avoid
// complicated row-level merge bugs in cash/accounting data.

const SYNC_SETTINGS_KEY = "kegelbruder_pwa_sync_settings";

function loadRawSettings() {
  try {
    return JSON.parse(localStorage.getItem(SYNC_SETTINGS_KEY) || "{}");
  } catch {
    return {};
  }
}

function saveRawSettings(settings) {
  localStorage.setItem(SYNC_SETTINGS_KEY, JSON.stringify(settings));
}

function defaultDeviceName() {
  const ua = navigator.userAgent || "";
  if (/iPad/i.test(ua) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)) return "iPad";
  if (/iPhone/i.test(ua)) return "iPhone";
  return "Browser";
}

function ensureDeviceId(settings) {
  if (settings.deviceId) return settings.deviceId;
  const id = crypto.randomUUID ? crypto.randomUUID() : `dev-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  settings.deviceId = id;
  saveRawSettings(settings);
  return id;
}

function normalizeEndpoint(endpoint) {
  return (endpoint || "").trim().replace(/\/+$/, "");
}

function bytesToBase64(bytes) {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

function base64ToBytes(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function assertConfigured(settings) {
  if (!settings.endpoint) throw new Error("Sync-Endpunkt fehlt.");
  if (!settings.clubId) throw new Error("Club-ID fehlt.");
  if (!settings.syncKey) throw new Error("Sync-Schlüssel fehlt.");
}

async function request(settings, path, options = {}) {
  assertConfigured(settings);
  const endpoint = normalizeEndpoint(settings.endpoint);
  const response = await fetch(`${endpoint}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${settings.syncKey}`,
      ...(options.headers || {}),
    },
  });
  const text = await response.text();
  let body = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = { message: text };
  }
  if (!response.ok) {
    const error = new Error(body?.message || `Sync fehlgeschlagen (${response.status})`);
    error.status = response.status;
    error.body = body;
    throw error;
  }
  return body;
}

export const SyncClient = {
  getSettings() {
    const settings = loadRawSettings();
    ensureDeviceId(settings);
    return {
      endpoint: settings.endpoint || "",
      clubId: settings.clubId || "kegelbrueder",
      syncKey: settings.syncKey || "",
      deviceName: settings.deviceName || defaultDeviceName(),
      deviceId: settings.deviceId,
      lastRevision: settings.lastRevision || null,
      lastSyncAt: settings.lastSyncAt || null,
    };
  },

  saveSettings(next) {
    const current = this.getSettings();
    const settings = {
      ...current,
      ...next,
      endpoint: normalizeEndpoint(next.endpoint ?? current.endpoint),
      clubId: (next.clubId ?? current.clubId).trim() || "kegelbrueder",
      syncKey: (next.syncKey ?? current.syncKey).trim(),
      deviceName: (next.deviceName ?? current.deviceName).trim() || defaultDeviceName(),
    };
    saveRawSettings(settings);
    return settings;
  },

  async status() {
    const settings = this.getSettings();
    return request(settings, `/sync/${encodeURIComponent(settings.clubId)}`);
  },

  async download() {
    const settings = this.getSettings();
    const remote = await request(settings, `/sync/${encodeURIComponent(settings.clubId)}?includeDb=1`);
    if (!remote.dbBase64) throw new Error("Remote enthält keine Datenbank.");
    const bytes = base64ToBytes(remote.dbBase64);
    this.saveSettings({
      lastRevision: remote.revision,
      lastSyncAt: new Date().toISOString(),
    });
    return { bytes, remote };
  },

  async upload(dbBytes) {
    const settings = this.getSettings();
    const payload = {
      baseRevision: settings.lastRevision,
      deviceId: settings.deviceId,
      deviceName: settings.deviceName,
      dbBase64: bytesToBase64(dbBytes),
    };
    const remote = await request(settings, `/sync/${encodeURIComponent(settings.clubId)}`, {
      method: "PUT",
      body: JSON.stringify(payload),
    });
    this.saveSettings({
      lastRevision: remote.revision,
      lastSyncAt: new Date().toISOString(),
    });
    return remote;
  },
};
