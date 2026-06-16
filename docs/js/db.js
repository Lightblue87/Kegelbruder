// Persistence layer — replaces the iOS SQLite/iCloud DataStore.
// Everything lives in localStorage as one JSON blob (small data set, no
// build tooling, fully offline). Export/Import lets the 3-4 club devices
// exchange a snapshot manually since there is no shared backend.

const STORAGE_KEY = "kegelbruder_v1";

export function defaultKasse() {
  return {
    Startgeld: 5.0,
    Pumpe: 0.5,
    Neuner: 1.0,
    Kranz: 2.0,
    Strafe_Stamm: 7.5,
    Bahngebuehr: 30.0,
    Kassenstand: 0.0,
    Kontostand: 0.0,
    Transaktionen: [],
    Letzte_Startgebuehren: 0.0,
  };
}

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

function defaultState() {
  return {
    mitglieder: {},
    kasse: defaultKasse(),
    aktuellesSpiel: { players: {}, runde: 0, abgerechnet: false, spieler_reihenfolge: null },
    historie: [],
    nextSpielId: 1,
    settings: { theme: "system" },
  };
}

let cache = null;

function load() {
  if (cache) return cache;
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      cache = JSON.parse(raw);
      // Backfill any missing fields from defaults (forward-compat)
      const d = defaultState();
      cache = { ...d, ...cache, kasse: { ...d.kasse, ...cache.kasse } };
      return cache;
    }
  } catch (e) {
    console.warn("Konnte gespeicherte Daten nicht lesen:", e);
  }
  cache = defaultState();
  return cache;
}

function save() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(cache));
  } catch (e) {
    console.error("Speichern fehlgeschlagen:", e);
  }
}

export const DB = {
  ladeMitglieder() {
    return load().mitglieder;
  },
  speichereMitglieder(players) {
    load().mitglieder = players;
    save();
  },
  ladeKasse() {
    return load().kasse;
  },
  speichereKasse(kasse) {
    load().kasse = kasse;
    save();
  },
  ladeAktuellesSpiel() {
    return load().aktuellesSpiel;
  },
  speichereAktuellesSpiel(spiel) {
    load().aktuellesSpiel = spiel;
    save();
  },
  ladeHistorie() {
    return load().historie;
  },
  archivierSpiel(datum, players, transaktionen, reihenfolge) {
    const state = load();
    const entry = {
      spielId: state.nextSpielId++,
      datum,
      players,
      transaktionen,
      spieler_reihenfolge: reihenfolge,
    };
    state.historie.push(entry);
    save();
    return entry;
  },
  getSettings() {
    return load().settings;
  },
  saveSettings(settings) {
    load().settings = { ...load().settings, ...settings };
    save();
  },
  exportJSON() {
    return JSON.stringify(load(), null, 2);
  },
  importJSON(json) {
    const parsed = JSON.parse(json);
    cache = { ...defaultState(), ...parsed };
    save();
  },
  resetAll() {
    cache = defaultState();
    save();
  },
};
