// Persistence layer — real SQLite running in the browser via sql.js
// (SQLite compiled to WebAssembly, vendored locally under ./vendor/sql-js/,
// no CDN dependency so the app stays fully offline-capable).
//
// Schema is identical to ios/KegelBrueder/Data/SQLiteStore.swift, which in
// turn matches the desktop Python app's kegelbruder.db. That means the very
// same .db file can be imported into the PWA (Einstellungen → Import) and
// exported back out again — no JSON conversion involved.
//
// sql.js itself is fully synchronous once loaded (it's just WASM running an
// in-memory database), so every accessor below stays synchronous exactly
// like the old localStorage-backed version — only `DB.init()` is async, and
// that's awaited once at app bootstrap in main.js before anything else runs.
// After every write we debounce-serialize the whole database (sql.js'
// `export()`) and persist the resulting bytes as a blob in IndexedDB, which
// is supported on every Safari version (unlike the File System Access API).

const IDB_NAME = "kegelbrueder-sqlite";
const IDB_STORE = "files";
const IDB_KEY = "kegelbruder.db";
const LEGACY_LOCALSTORAGE_KEY = "kegelbruder_v1"; // from the first JSON-based PWA build
const UI_SETTINGS_KEY = "kegelbruder_pwa_ui_settings"; // PWA-only prefs, not part of the club schema

const SCHEMA_SQL = `
CREATE TABLE IF NOT EXISTS mitglieder (
    name TEXT PRIMARY KEY,
    typ TEXT NOT NULL DEFAULT 'Stamm',
    offene_zahlung REAL NOT NULL DEFAULT 0.0
);
CREATE TABLE IF NOT EXISTS kasse_einstellungen (
    schluessel TEXT PRIMARY KEY,
    wert REAL NOT NULL DEFAULT 0.0
);
CREATE TABLE IF NOT EXISTS transaktionen (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    text TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS aktuelles_spiel_spieler (
    name TEXT PRIMARY KEY,
    typ TEXT NOT NULL DEFAULT 'Stamm',
    punkte_r1 INTEGER NOT NULL DEFAULT 0,
    punkte_r2 INTEGER NOT NULL DEFAULT 0,
    punkte_r3 INTEGER NOT NULL DEFAULT 0,
    punkte_r4 INTEGER NOT NULL DEFAULT 0,
    pumpen INTEGER NOT NULL DEFAULT 0,
    neuner INTEGER NOT NULL DEFAULT 0,
    kranz INTEGER NOT NULL DEFAULT 0,
    position INTEGER NOT NULL DEFAULT 0,
    offene_zahlung REAL NOT NULL DEFAULT 0.0
);
CREATE TABLE IF NOT EXISTS aktuelles_spiel_meta (
    schluessel TEXT PRIMARY KEY,
    wert TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS historie (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    datum TEXT NOT NULL,
    spieler_reihenfolge TEXT
);
CREATE TABLE IF NOT EXISTS historie_spieler (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    spiel_id INTEGER NOT NULL REFERENCES historie(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    typ TEXT,
    punkte_r1 INTEGER DEFAULT 0,
    punkte_r2 INTEGER DEFAULT 0,
    punkte_r3 INTEGER DEFAULT 0,
    punkte_r4 INTEGER DEFAULT 0,
    pumpen INTEGER DEFAULT 0,
    neuner INTEGER DEFAULT 0,
    kranz INTEGER DEFAULT 0,
    offene_zahlung REAL DEFAULT 0.0
);
CREATE TABLE IF NOT EXISTS historie_transaktionen (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    spiel_id INTEGER NOT NULL REFERENCES historie(id) ON DELETE CASCADE,
    text TEXT NOT NULL
);
`;

const DEFAULT_KASSE_EINSTELLUNGEN = [
  ["Startgeld", 5.0],
  ["Pumpe", 0.5],
  ["Neuner", 1.0],
  ["Kranz", 2.0],
  ["Strafe Stamm", 7.5],
  ["Bahngebühr", 30.0],
  ["Kassenstand", 0.0],
  ["Kontostand", 0.0],
  ["Letzte_Startgebuehren", 0.0],
];

export function defaultPlayerData(typ = "Stamm") {
  return {
    typ,
    punkte: [0, 0, 0, 0],
    offene_zahlung: 0.0,
    pumpen: 0,
    neuner: 0,
    kranz: 0,
    position: null,
  };
}

// ---------------------------------------------------------------- IndexedDB blob storage

function idbOpen() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(IDB_NAME, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(IDB_STORE);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function idbLoad() {
  const db = await idbOpen();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(IDB_STORE, "readonly");
    const req = tx.objectStore(IDB_STORE).get(IDB_KEY);
    req.onsuccess = () => resolve(req.result || null);
    req.onerror = () => reject(req.error);
  });
}

async function idbSave(bytes) {
  const db = await idbOpen();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(IDB_STORE, "readwrite");
    tx.objectStore(IDB_STORE).put(bytes, IDB_KEY);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

// ---------------------------------------------------------------- sql.js database handle

let SQL = null;
let sq = null; // sql.js Database instance
let saveTimer = null;

function ensureDefaultKasse() {
  for (const [key, val] of DEFAULT_KASSE_EINSTELLUNGEN) {
    sq.run("INSERT OR IGNORE INTO kasse_einstellungen (schluessel, wert) VALUES (?, ?)", [key, val]);
  }
}

function persist() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    const bytes = sq.export();
    idbSave(bytes).catch((e) => console.error("SQLite-Speichern in IndexedDB fehlgeschlagen:", e));
  }, 80);
}

function queryAll(sql, params = []) {
  const stmt = sq.prepare(sql);
  stmt.bind(params);
  const rows = [];
  while (stmt.step()) rows.push(stmt.getAsObject());
  stmt.free();
  return rows;
}

function run(sql, params = []) {
  sq.run(sql, params);
}

function withTransaction(block) {
  sq.run("BEGIN");
  try {
    block();
    sq.run("COMMIT");
  } catch (e) {
    sq.run("ROLLBACK");
    throw e;
  }
}

/** One-time migration from the very first (JSON/localStorage) PWA build, if present. */
function migrateLegacyJsonIfPresent() {
  const raw = localStorage.getItem(LEGACY_LOCALSTORAGE_KEY);
  if (!raw) return;
  try {
    const legacy = JSON.parse(raw);
    withTransaction(() => {
      for (const [name, d] of Object.entries(legacy.mitglieder || {})) {
        run("INSERT OR REPLACE INTO mitglieder (name, typ, offene_zahlung) VALUES (?, ?, ?)", [name, d.typ, d.offene_zahlung || 0]);
      }
      const k = legacy.kasse || {};
      const map = {
        Startgeld: k.Startgeld, Pumpe: k.Pumpe, Neuner: k.Neuner, Kranz: k.Kranz,
        "Strafe Stamm": k.Strafe_Stamm, "Bahngebühr": k.Bahngebuehr,
        Kassenstand: k.Kassenstand, Kontostand: k.Kontostand,
        Letzte_Startgebuehren: k.Letzte_Startgebuehren,
      };
      for (const [key, val] of Object.entries(map)) {
        if (val !== undefined) run("INSERT OR REPLACE INTO kasse_einstellungen (schluessel, wert) VALUES (?, ?)", [key, val]);
      }
      for (const tx of k.Transaktionen || []) run("INSERT INTO transaktionen (text) VALUES (?)", [tx]);

      const spiel = legacy.aktuellesSpiel || {};
      const reihenfolge = spiel.spieler_reihenfolge || Object.keys(spiel.players || {});
      reihenfolge.forEach((name, idx) => {
        const d = (spiel.players || {})[name];
        if (!d) return;
        const p = Array.isArray(d.punkte) && d.punkte.length === 4 ? d.punkte : [0, 0, 0, 0];
        run(
          `INSERT OR REPLACE INTO aktuelles_spiel_spieler
           (name,typ,punkte_r1,punkte_r2,punkte_r3,punkte_r4,pumpen,neuner,kranz,position,offene_zahlung)
           VALUES (?,?,?,?,?,?,?,?,?,?,?)`,
          [name, d.typ, p[0], p[1], p[2], p[3], d.pumpen || 0, d.neuner || 0, d.kranz || 0, idx, d.offene_zahlung || 0]
        );
      });
      run("INSERT OR REPLACE INTO aktuelles_spiel_meta (schluessel, wert) VALUES (?, ?)", ["runde", String(spiel.runde || 0)]);
      run("INSERT OR REPLACE INTO aktuelles_spiel_meta (schluessel, wert) VALUES (?, ?)", ["abgerechnet", spiel.abgerechnet ? "true" : "false"]);
      run("INSERT OR REPLACE INTO aktuelles_spiel_meta (schluessel, wert) VALUES (?, ?)", ["spieler_reihenfolge", JSON.stringify(reihenfolge)]);

      for (const entry of legacy.historie || []) {
        run("INSERT INTO historie (datum, spieler_reihenfolge) VALUES (?, ?)", [entry.datum, JSON.stringify(entry.spieler_reihenfolge || [])]);
        const spielId = sq.exec("SELECT last_insert_rowid()")[0].values[0][0];
        const order = entry.spieler_reihenfolge || Object.keys(entry.players || {});
        for (const name of order) {
          const d = (entry.players || {})[name];
          if (!d) continue;
          const p = Array.isArray(d.punkte) && d.punkte.length === 4 ? d.punkte : [0, 0, 0, 0];
          run(
            `INSERT INTO historie_spieler (spiel_id,name,typ,punkte_r1,punkte_r2,punkte_r3,punkte_r4,pumpen,neuner,kranz,offene_zahlung)
             VALUES (?,?,?,?,?,?,?,?,?,?,?)`,
            [spielId, name, d.typ, p[0], p[1], p[2], p[3], d.pumpen || 0, d.neuner || 0, d.kranz || 0, d.offene_zahlung || 0]
          );
        }
        for (const tx of entry.transaktionen || []) {
          run("INSERT INTO historie_transaktionen (spiel_id, text) VALUES (?, ?)", [spielId, tx]);
        }
      }
    });
    console.info("Alte JSON-Daten (erste PWA-Version) wurden einmalig in die SQLite-Datenbank übernommen.");
  } catch (e) {
    console.warn("Migration der alten JSON-Daten fehlgeschlagen, wird ignoriert:", e);
  } finally {
    localStorage.removeItem(LEGACY_LOCALSTORAGE_KEY);
  }
}

async function openFresh(bytes) {
  sq = bytes ? new SQL.Database(new Uint8Array(bytes)) : new SQL.Database();
  sq.run(SCHEMA_SQL);
  ensureDefaultKasse();
}

export const DB = {
  /** Must be awaited once at app bootstrap before any other DB.* call. */
  async init() {
    if (sq) return;
    // sql-wasm.js is loaded as a classic <script> in index.html and exposes
    // the global `initSqlJs` factory. Its own default path-resolution relies
    // on `document.currentScript`, which isn't reliably available by the time
    // the async wasm fetch actually runs — so resolve the path explicitly,
    // relative to this module's own URL.
    const wasmDir = new URL("../vendor/sql-js/", import.meta.url).href;
    SQL = await window.initSqlJs({ locateFile: (file) => wasmDir + file });
    const existing = await idbLoad();
    await openFresh(existing);
    if (!existing) migrateLegacyJsonIfPresent();
    persist();
  },

  // ---- Mitglieder ----
  ladeMitglieder() {
    const result = {};
    for (const row of queryAll("SELECT name, typ, offene_zahlung FROM mitglieder")) {
      result[row.name] = defaultPlayerData(row.typ);
      result[row.name].offene_zahlung = row.offene_zahlung;
    }
    return result;
  },
  speichereMitglieder(players) {
    withTransaction(() => {
      run("DELETE FROM mitglieder");
      for (const [name, d] of Object.entries(players)) {
        run("INSERT INTO mitglieder (name, typ, offene_zahlung) VALUES (?, ?, ?)", [name, d.typ, d.offene_zahlung]);
      }
    });
    persist();
  },

  // ---- Kasse ----
  ladeKasse() {
    const e = {};
    for (const row of queryAll("SELECT schluessel, wert FROM kasse_einstellungen")) e[row.schluessel] = row.wert;
    return {
      Startgeld: e["Startgeld"] ?? 5.0,
      Pumpe: e["Pumpe"] ?? 0.5,
      Neuner: e["Neuner"] ?? 1.0,
      Kranz: e["Kranz"] ?? 2.0,
      Strafe_Stamm: e["Strafe Stamm"] ?? 7.5,
      Bahngebuehr: e["Bahngebühr"] ?? 30.0,
      Kassenstand: e["Kassenstand"] ?? 0.0,
      Kontostand: e["Kontostand"] ?? 0.0,
      Transaktionen: queryAll("SELECT text FROM transaktionen ORDER BY id ASC").map((r) => r.text),
      Letzte_Startgebuehren: e["Letzte_Startgebuehren"] ?? 0.0,
    };
  },
  speichereKasse(kasse) {
    const map = {
      Startgeld: kasse.Startgeld,
      Pumpe: kasse.Pumpe,
      Neuner: kasse.Neuner,
      Kranz: kasse.Kranz,
      "Strafe Stamm": kasse.Strafe_Stamm,
      "Bahngebühr": kasse.Bahngebuehr,
      Kassenstand: kasse.Kassenstand,
      Kontostand: kasse.Kontostand,
      Letzte_Startgebuehren: kasse.Letzte_Startgebuehren,
    };
    withTransaction(() => {
      for (const [key, val] of Object.entries(map)) {
        run("INSERT OR REPLACE INTO kasse_einstellungen (schluessel, wert) VALUES (?, ?)", [key, val]);
      }
      run("DELETE FROM transaktionen");
      for (const tx of kasse.Transaktionen) run("INSERT INTO transaktionen (text) VALUES (?)", [tx]);
    });
    persist();
  },

  // ---- Aktuelles Spiel ----
  ladeAktuellesSpiel() {
    const players = {};
    for (const row of queryAll(
      `SELECT name, typ, punkte_r1, punkte_r2, punkte_r3, punkte_r4, pumpen, neuner, kranz, position, offene_zahlung
       FROM aktuelles_spiel_spieler ORDER BY position`
    )) {
      players[row.name] = {
        typ: row.typ,
        punkte: [row.punkte_r1, row.punkte_r2, row.punkte_r3, row.punkte_r4],
        offene_zahlung: row.offene_zahlung,
        pumpen: row.pumpen,
        neuner: row.neuner,
        kranz: row.kranz,
        position: row.position,
      };
    }
    const meta = {};
    for (const row of queryAll("SELECT schluessel, wert FROM aktuelles_spiel_meta")) meta[row.schluessel] = row.wert;
    let reihenfolge = null;
    try {
      reihenfolge = JSON.parse(meta.spieler_reihenfolge || "[]");
    } catch {
      reihenfolge = null;
    }
    return {
      players,
      runde: parseInt(meta.runde || "0", 10) || 0,
      abgerechnet: meta.abgerechnet === "true",
      spieler_reihenfolge: reihenfolge,
    };
  },
  speichereAktuellesSpiel(spiel) {
    withTransaction(() => {
      run("DELETE FROM aktuelles_spiel_spieler");
      const order = spiel.spieler_reihenfolge || Object.keys(spiel.players);
      order.forEach((name, idx) => {
        const d = spiel.players[name];
        if (!d) return;
        const p = Array.isArray(d.punkte) && d.punkte.length === 4 ? d.punkte : [0, 0, 0, 0];
        run(
          `INSERT INTO aktuelles_spiel_spieler
           (name,typ,punkte_r1,punkte_r2,punkte_r3,punkte_r4,pumpen,neuner,kranz,position,offene_zahlung)
           VALUES (?,?,?,?,?,?,?,?,?,?,?)`,
          [name, d.typ, p[0], p[1], p[2], p[3], d.pumpen || 0, d.neuner || 0, d.kranz || 0, idx, d.offene_zahlung]
        );
      });
      run("DELETE FROM aktuelles_spiel_meta");
      run("INSERT INTO aktuelles_spiel_meta (schluessel, wert) VALUES ('runde', ?)", [String(spiel.runde)]);
      run("INSERT INTO aktuelles_spiel_meta (schluessel, wert) VALUES ('abgerechnet', ?)", [spiel.abgerechnet ? "true" : "false"]);
      run("INSERT INTO aktuelles_spiel_meta (schluessel, wert) VALUES ('spieler_reihenfolge', ?)", [JSON.stringify(order)]);
    });
    persist();
  },

  // ---- Historie ----
  ladeHistorie() {
    const entries = [];
    for (const spiel of queryAll("SELECT id, datum, spieler_reihenfolge FROM historie ORDER BY id ASC")) {
      const players = {};
      for (const row of queryAll(
        `SELECT name, typ, punkte_r1, punkte_r2, punkte_r3, punkte_r4, pumpen, neuner, kranz, offene_zahlung
         FROM historie_spieler WHERE spiel_id = ?`,
        [spiel.id]
      )) {
        players[row.name] = {
          typ: row.typ,
          punkte: [row.punkte_r1, row.punkte_r2, row.punkte_r3, row.punkte_r4],
          offene_zahlung: row.offene_zahlung,
          pumpen: row.pumpen,
          neuner: row.neuner,
          kranz: row.kranz,
          position: null,
        };
      }
      const transaktionen = queryAll("SELECT text FROM historie_transaktionen WHERE spiel_id = ? ORDER BY id ASC", [spiel.id]).map(
        (r) => r.text
      );
      let reihenfolge = [];
      try {
        reihenfolge = JSON.parse(spiel.spieler_reihenfolge || "[]");
      } catch {
        reihenfolge = [];
      }
      entries.push({ spielId: spiel.id, datum: spiel.datum, players, transaktionen, spieler_reihenfolge: reihenfolge });
    }
    return entries;
  },
  archivierSpiel(datum, players, transaktionen, reihenfolge) {
    let entry;
    withTransaction(() => {
      run("INSERT INTO historie (datum, spieler_reihenfolge) VALUES (?, ?)", [datum, JSON.stringify(reihenfolge)]);
      const spielId = sq.exec("SELECT last_insert_rowid()")[0].values[0][0];
      for (const name of reihenfolge) {
        const d = players[name];
        if (!d) continue;
        const p = Array.isArray(d.punkte) && d.punkte.length === 4 ? d.punkte : [0, 0, 0, 0];
        run(
          `INSERT INTO historie_spieler (spiel_id,name,typ,punkte_r1,punkte_r2,punkte_r3,punkte_r4,pumpen,neuner,kranz,offene_zahlung)
           VALUES (?,?,?,?,?,?,?,?,?,?,?)`,
          [spielId, name, d.typ, p[0], p[1], p[2], p[3], d.pumpen || 0, d.neuner || 0, d.kranz || 0, d.offene_zahlung]
        );
      }
      for (const tx of transaktionen) run("INSERT INTO historie_transaktionen (spiel_id, text) VALUES (?, ?)", [spielId, tx]);
      entry = { spielId, datum, players, transaktionen, spieler_reihenfolge: reihenfolge };
    });
    persist();
    return entry;
  },

  // ---- PWA-only UI settings (theme) — kept separate from the club schema ----
  getSettings() {
    try {
      return JSON.parse(localStorage.getItem(UI_SETTINGS_KEY) || "{}");
    } catch {
      return {};
    }
  },
  saveSettings(settings) {
    const current = DB.getSettings();
    localStorage.setItem(UI_SETTINGS_KEY, JSON.stringify({ ...current, ...settings }));
  },

  // ---- Export / Import as a real .db file ----
  exportDb() {
    return sq.export(); // Uint8Array — same binary format as kegelbruder.db
  },
  async importDb(bytes) {
    sq.close();
    await openFresh(bytes);
    persist();
  },

  resetAll() {
    sq.close();
    sq = new SQL.Database();
    sq.run(SCHEMA_SQL);
    ensureDefaultKasse();
    persist();
  },
};
