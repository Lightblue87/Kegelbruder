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
const LEGACY_MIGRATION_DONE_KEY = "kegelbruder_v1_migrated";
const UI_SETTINGS_KEY = "kegelbruder_pwa_ui_settings"; // PWA-only prefs, not part of the club schema
// vollname is PWA-only and stored in localStorage so Desktop/iOS DELETE+re-insert cycles
// can never wipe it (those clients omit the column entirely).
const VOLLNAME_KEY = "kegelbruder_vollnamen"; // { [name]: vollname }

function ladeVollnamen() {
  try { return JSON.parse(localStorage.getItem(VOLLNAME_KEY) || "{}"); } catch { return {}; }
}
function speichereVollnamen(map) {
  localStorage.setItem(VOLLNAME_KEY, JSON.stringify(map));
}

const SCHEMA_SQL = `
CREATE TABLE IF NOT EXISTS mitglieder (
    name TEXT PRIMARY KEY,
    vollname TEXT NOT NULL DEFAULT '',
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
    spieler_reihenfolge TEXT,
    notiz TEXT NOT NULL DEFAULT ''
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
CREATE TABLE IF NOT EXISTS regeln (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    paragraph INTEGER NOT NULL,
    absatz INTEGER NOT NULL,
    paragraf_titel TEXT NOT NULL DEFAULT '',
    absatz_titel TEXT NOT NULL DEFAULT '',
    regel_text TEXT NOT NULL DEFAULT '',
    betrag_strafe TEXT NOT NULL DEFAULT ''
);
`;

const DEFAULT_REGELN = [
  [1,1,"§1 Der Stamm","Grundsatz","Der Stamm entscheidet mit der demokratischen Entscheidungsform per Mehrheit über:",""],
  [1,2,"§1 Der Stamm","Mitglieder","… die Aufnahme neuer Mitglieder in den Stamm.",""],
  [1,3,"§1 Der Stamm","Ausschluss","… den Ausschluss aus dem Stamm (ggf. auch Schuldenerlass).",""],
  [1,4,"§1 Der Stamm","Regeln","… die Anpassung, das Aussetzen, das Hinzufügen von Regeln.",""],
  [1,5,"§1 Der Stamm","Kassenbudget","… die Nutzung des Kassenbudgets.",""],
  [1,6,"§1 Der Stamm","Strafen","… die Anpassung, das Aussetzen, das Hinzufügen von Strafen.",""],
  [2,1,"§2 Gebühren","Anwesenheit Stamm","Jedes Stammmitglied, welches im Stammbuch eingetragen ist, entrichtet p. stattgefundenes Treffen 5 € Startgebühr in die Kegelkasse – dies erfolgt unabhängig von der physischen Anwesenheit. Strafen der folgenden Absätze sind hinzuzurechnen.","5 €"],
  [2,2,"§2 Gebühren","Passive Anwesenheit","Passive Anwesenheit befreit von den Strafzahlungen für Abwesenheit, wenn das Stammmitglied anwesend ist, bevor es in der Kegelfolge aktiv werden müsste (2. Runde nicht gestartet).","Befreiung"],
  [2,3,"§2 Gebühren","Abwesenheit","Abwesende Stammmitglieder entrichten für den Ausfall der während des Spiels entstehenden Strafzahlungen eine Pauschale.","2,50 €"],
  [2,4,"§2 Gebühren","Anwesenheit des Stamms kleiner als 50 %","An Treffen, an denen weniger als 50 % des Stammes anwesend sind, gilt es für die Abwesenden einen Zusatzbeitrag zu entrichten.","5 €"],
  [2,5,"§2 Gebühren","Entrichtung der Kegelgebühren","Ein Mitglied des Vorstandes oder ein Stammmitglied begleicht p. Treffen an den Gastwirt die Gebühren für die Kegelbahn aus dem Budget der Kasse und lässt sich dies gegenzeichnen.","30 €"],
  [4,1,"§4 Kegelregeln","Kugel im Raum","Wer den Gastroraum mit Kugel betritt, zahlt eine Runde.","Runde"],
  [4,2,"§4 Kegelregeln","Überworfen","Wer mehr als 10 Würfe ohne Abstimmung macht, zahlt eine Runde.","Runde"],
  [4,3,"§4 Kegelregeln","Fangen der Kugel","Wenn die eigene Kugel von einem anderen gefangen wird (weil zu langsam), zahlt der Werfer eine Runde.","Runde"],
  [4,4,"§4 Kegelregeln","Gescheiterter Versuch","Wer versucht eine Kugel zu fangen, aber ohne diese wieder zurück über die Abwurflinie kommt, zahlt eine Runde.","Runde"],
  [4,5,"§4 Kegelregeln","10× gleicher Wurf","Wer z.B. 10× die 7 wirft, zahlt eine Runde.","Runde"],
  [5,1,"§5 Stechen","Pumpen-Gleichstand","Gleiche Anzahl an Pumpen nach 4 Runden muss gestochen werden (1. & 2. Pumpe).","Runde"],
  [5,2,"§5 Stechen","Punktgleichstand","Egal welcher Platz – Punktgleichstand nach 4 Runden muss gestochen werden!","Runde"],
];

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

function applyMigrations() {
  // v2: notiz column on historie
  const historieCols = (sq.exec("PRAGMA table_info(historie)")[0]?.values ?? []).map((r) => r[1]);
  if (!historieCols.includes("notiz")) {
    sq.run("ALTER TABLE historie ADD COLUMN notiz TEXT NOT NULL DEFAULT ''");
  }
  // v3: vollname column on mitglieder
  const mitgliederCols = (sq.exec("PRAGMA table_info(mitglieder)")[0]?.values ?? []).map((r) => r[1]);
  if (!mitgliederCols.includes("vollname")) {
    sq.run("ALTER TABLE mitglieder ADD COLUMN vollname TEXT NOT NULL DEFAULT ''");
  }
  // Seed regeln only on a truly fresh DB (no marker set), not when a user has
  // intentionally emptied the table. The marker is set once on first seed and
  // persists across imports so deleted rules stay deleted.
  const regelnSeeded = sq.exec("SELECT wert FROM kasse_einstellungen WHERE schluessel = 'regeln_seeded'")[0]?.values[0]?.[0];
  const hasRegeln = sq.exec("SELECT COUNT(*) FROM regeln")[0].values[0][0] > 0;
  if (!hasRegeln && !regelnSeeded) {
    for (const [para, abs, ptitel, atitel, text, betrag] of DEFAULT_REGELN) {
      sq.run(
        "INSERT INTO regeln (paragraph,absatz,paragraf_titel,absatz_titel,regel_text,betrag_strafe) VALUES (?,?,?,?,?,?)",
        [para, abs, ptitel, atitel, text, betrag]
      );
    }
    sq.run("INSERT OR REPLACE INTO kasse_einstellungen (schluessel, wert) VALUES ('regeln_seeded', '1')");
  } else if (hasRegeln && !regelnSeeded) {
    // Imported DB that already has rules — mark as seeded so future empties aren't re-seeded.
    sq.run("INSERT OR REPLACE INTO kasse_einstellungen (schluessel, wert) VALUES ('regeln_seeded', '1')");
  }
}

function persist() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    const bytes = sq.export();
    idbSave(bytes).catch((e) => console.error("SQLite-Speichern in IndexedDB fehlgeschlagen:", e));
  }, 80);
}

async function persistNow() {
  clearTimeout(saveTimer);
  const bytes = sq.export();
  await idbSave(bytes);
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
  if (localStorage.getItem(LEGACY_MIGRATION_DONE_KEY) === "1") {
    localStorage.removeItem(LEGACY_LOCALSTORAGE_KEY);
    return;
  }
  try {
    const legacy = JSON.parse(raw);
    withTransaction(() => {
      run("DELETE FROM historie_transaktionen");
      run("DELETE FROM historie_spieler");
      run("DELETE FROM historie");
      run("DELETE FROM aktuelles_spiel_meta");
      run("DELETE FROM aktuelles_spiel_spieler");
      run("DELETE FROM transaktionen");
      run("DELETE FROM mitglieder");
      run("DELETE FROM kasse_einstellungen");
      ensureDefaultKasse();

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
    persistNow()
      .then(() => {
        localStorage.setItem(LEGACY_MIGRATION_DONE_KEY, "1");
        localStorage.removeItem(LEGACY_LOCALSTORAGE_KEY);
        console.info("Alte JSON-Daten (erste PWA-Version) wurden einmalig in die SQLite-Datenbank übernommen.");
      })
      .catch((saveError) => {
        console.warn("Migration gespeichert, aber IndexedDB-Sicherung ist fehlgeschlagen. Legacy-Daten bleiben erhalten:", saveError);
      });
  } catch (e) {
    console.warn("Migration der alten JSON-Daten fehlgeschlagen. Legacy-Daten bleiben erhalten:", e);
  }
}

async function openFresh(bytes) {
  sq = bytes ? new SQL.Database(new Uint8Array(bytes)) : new SQL.Database();
  sq.run(SCHEMA_SQL);
  ensureDefaultKasse();
  applyMigrations();
}

function openValidated(bytes) {
  const normalized = bytes ? new Uint8Array(bytes) : null;
  if (normalized && normalized.length === 0) throw new Error("Datei ist leer.");
  if (normalized) {
    const magic = "SQLite format 3\0";
    const header = String.fromCharCode(...normalized.slice(0, magic.length));
    if (header !== magic) throw new Error("Datei ist keine SQLite-Datenbank.");
  }
  const next = normalized ? new SQL.Database(normalized) : new SQL.Database();
  try {
    next.run(SCHEMA_SQL);
    for (const table of ["mitglieder", "kasse_einstellungen", "transaktionen"]) {
      next.exec(`SELECT 1 FROM ${table} LIMIT 1`);
    }
    return next;
  } catch (e) {
    next.close();
    throw e;
  }
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
    const vollnamen = ladeVollnamen();
    const result = {};
    for (const row of queryAll("SELECT name, vollname, typ, offene_zahlung FROM mitglieder")) {
      result[row.name] = defaultPlayerData(row.typ);
      // localStorage takes precedence — Desktop/iOS re-inserts wipe the DB column
      result[row.name].vollname = vollnamen[row.name] ?? row.vollname ?? "";
      result[row.name].offene_zahlung = row.offene_zahlung;
    }
    return result;
  },
  speichereMitglieder(players) {
    // Persist vollname to localStorage so it survives Desktop/iOS DB overwrites.
    const vollnamen = ladeVollnamen();
    for (const [name, d] of Object.entries(players)) {
      if (d.vollname) vollnamen[name] = d.vollname;
      else delete vollnamen[name];
    }
    // Remove entries for deleted members.
    for (const name of Object.keys(vollnamen)) {
      if (!players[name]) delete vollnamen[name];
    }
    speichereVollnamen(vollnamen);

    withTransaction(() => {
      run("DELETE FROM mitglieder");
      for (const [name, d] of Object.entries(players)) {
        run("INSERT INTO mitglieder (name, vollname, typ, offene_zahlung) VALUES (?, ?, ?, ?)", [name, d.vollname || "", d.typ, d.offene_zahlung]);
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
    for (const spiel of queryAll("SELECT id, datum, spieler_reihenfolge, notiz FROM historie ORDER BY id ASC")) {
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
      entries.push({ spielId: spiel.id, datum: spiel.datum, players, transaktionen, spieler_reihenfolge: reihenfolge, notiz: spiel.notiz || "" });
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

  speichereHistorieNotiz(spielId, notiz) {
    run("UPDATE historie SET notiz = ? WHERE id = ?", [notiz, spielId]);
    persist();
  },

  löscheHistorieEintrag(spielId) {
    withTransaction(() => {
      run("DELETE FROM historie_transaktionen WHERE spiel_id = ?", [spielId]);
      run("DELETE FROM historie_spieler WHERE spiel_id = ?", [spielId]);
      run("DELETE FROM historie WHERE id = ?", [spielId]);
    });
    persist();
  },

  // ---- Regeln ----
  ladeRegeln() {
    return queryAll("SELECT id, paragraph, absatz, paragraf_titel, absatz_titel, regel_text, betrag_strafe FROM regeln ORDER BY paragraph, absatz, id");
  },
  speichereRegel(id, regelText, betragStrafe) {
    run("UPDATE regeln SET regel_text = ?, betrag_strafe = ? WHERE id = ?", [regelText, betragStrafe, id]);
    persist();
  },
  neueRegel({ paragraph, paragrafTitel, absatzTitel, regelText, betragStrafe }) {
    let newId;
    withTransaction(() => {
      const nextAbsatz = queryAll("SELECT COALESCE(MAX(absatz), 0) + 1 AS n FROM regeln WHERE paragraph = ?", [paragraph])[0].n;
      run(
        "INSERT INTO regeln (paragraph,absatz,paragraf_titel,absatz_titel,regel_text,betrag_strafe) VALUES (?,?,?,?,?,?)",
        [paragraph, nextAbsatz, paragrafTitel, absatzTitel, regelText, betragStrafe]
      );
      newId = sq.exec("SELECT last_insert_rowid()")[0].values[0][0];
    });
    persist();
    return newId;
  },
  naechsterParagraph() {
    return queryAll("SELECT COALESCE(MAX(paragraph), 0) + 1 AS n FROM regeln")[0].n;
  },
  loescheRegel(id) {
    run("DELETE FROM regeln WHERE id = ?", [id]);
    persist();
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
    const next = openValidated(bytes);
    const previous = sq;
    sq = next;
    ensureDefaultKasse();
    applyMigrations();
    try {
      await persistNow();
      previous.close();
    } catch (e) {
      sq.close();
      sq = previous;
      throw e;
    }
  },

  resetAll() {
    sq.close();
    sq = new SQL.Database();
    sq.run(SCHEMA_SQL);
    ensureDefaultKasse();
    persist();
  },
};
