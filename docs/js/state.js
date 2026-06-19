// Central app store — 1:1 port of ios/KegelBrueder/ViewModels/AppViewModel.swift
import { DB, defaultPlayerData } from "./db.js";
import { round2, formatDatum, money } from "./format.js";

function clone(obj) {
  return JSON.parse(JSON.stringify(obj));
}

function toPlayerData(player) {
  return {
    typ: player.typ,
    punkte: player.punkte,
    offene_zahlung: player.offene_zahlung,
    pumpen: player.pumpen,
    neuner: player.neuner,
    kranz: player.kranz,
    position: player.position ?? null,
  };
}

function playerFromData(name, data) {
  return {
    name,
    typ: data.typ,
    punkte: Array.isArray(data.punkte) && data.punkte.length === 4 ? [...data.punkte] : [0, 0, 0, 0],
    offene_zahlung: data.offene_zahlung || 0,
    pumpen: data.pumpen || 0,
    neuner: data.neuner || 0,
    kranz: data.kranz || 0,
    position: data.position ?? null,
  };
}

function newPlayer(name, typ = "Stamm") {
  return { name, typ, punkte: [0, 0, 0, 0], offene_zahlung: 0, pumpen: 0, neuner: 0, kranz: 0, position: null };
}

function summe(player) {
  return player.punkte.reduce((a, b) => a + b, 0);
}

function namesEqual(a, b) {
  return a.trim().toLowerCase() === b.trim().toLowerCase();
}

function uniqueNames(names) {
  const seen = new Set();
  const result = [];
  for (const name of names) {
    const key = name.trim().toLowerCase();
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(name);
  }
  return result;
}

function uniquePlayersByName(players) {
  const seen = new Set();
  const result = [];
  for (const p of players) {
    const key = p.name.trim().toLowerCase();
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(p);
  }
  return result;
}

class Store {
  constructor() {
    this.listeners = [];

    this.kasse = DB.ladeKasse();
    this.mitglieder = DB.ladeMitglieder();
    this.players = [];
    this.runde = 0;
    this.abgerechnet = false;
    this.gameRunning = false;

    this.billingRows = [];
    this.billingGezahlt = {};
    this.tiebreakExtras = {};
    this.pumpRank = {};

    this.sessionTx = [];
    this.preSessionSchulden = {};

    this.pendingAttendees = [];
    this.pendingGäste = [];

    this.archivFehler = null;

    // Navigation (sheets are managed imperatively by main.js, not reactively)
    this.route = null; // null | "game" | "cash" | "players" | "archive" | "settings"
    this.alert = null; // {title, message, buttons:[{label,role,onClick}]}

    this._ladeAktuellesSpiel();
  }

  subscribe(fn) {
    this.listeners.push(fn);
  }
  notify() {
    this.listeners.forEach((fn) => fn());
  }

  // ---------------------------------------------------------------- Load

  laden() {
    this.kasse = DB.ladeKasse();
    this.mitglieder = DB.ladeMitglieder();
    this._ladeAktuellesSpiel();
  }

  _ladeAktuellesSpiel() {
    const spiel = DB.ladeAktuellesSpiel();
    this.abgerechnet = spiel.abgerechnet;
    const order = spiel.spieler_reihenfolge || Object.keys(spiel.players).sort();
    this.players = order.filter((n) => spiel.players[n]).map((n) => playerFromData(n, spiel.players[n]));
    this.gameRunning = Object.keys(spiel.players).length > 0;
  }

  // ---------------------------------------------------------------- New game flow

  /** Returns true if the attendance sheet should be opened, false if it bailed out. */
  starteNeuesSpiel() {
    if (this.gameRunning) return false;
    this.laden();
    if (Object.keys(this.mitglieder).length === 0) {
      this.alert = {
        title: "Keine Spieler",
        message: "Bitte zuerst unter „Spieler verwalten“ Mitglieder anlegen.",
        buttons: [{ label: "OK", role: "cancel" }],
      };
      this.notify();
      return false;
    }
    this.sessionTx = [];
    this.preSessionSchulden = {};
    this.pendingAttendees = [];
    this.pendingGäste = [];
    this.tiebreakExtras = {};
    this.pumpRank = {};
    this.billingRows = [];
    this.billingGezahlt = {};
    this.runde = 1;
    this.abgerechnet = false;
    this.notify();
    return true;
  }

  // ---------------------------------------------------------------- Attendance

  berechneStartgebuehren(anwesend, zahlungen) {
    this.preSessionSchulden = {};
    const aktuelleMitglieder = clone(DB.ladeMitglieder());

    for (const [name, player] of Object.entries(aktuelleMitglieder)) {
      this.preSessionSchulden[name] = player.offene_zahlung;
    }

    for (const [name, istAnwesend] of Object.entries(anwesend)) {
      if (!aktuelleMitglieder[name]) continue;
      if (istAnwesend) aktuelleMitglieder[name].offene_zahlung += this.kasse.Startgeld;
      else aktuelleMitglieder[name].offene_zahlung += this.kasse.Strafe_Stamm;
    }

    for (const [name, betrag] of Object.entries(zahlungen)) {
      if (!(betrag > 0)) continue;
      const pd = aktuelleMitglieder[name];
      if (!pd) continue;
      const datum = formatDatum();
      const beschreibung = betrag >= pd.offene_zahlung ? `Zahlung von ${name}` : `Teilzahlung von ${name}`;
      pd.offene_zahlung = Math.max(0, round2(pd.offene_zahlung - betrag));
      const text = this._addEinzahlung(betrag, beschreibung, datum);
      this.sessionTx.push({ kind: "einzahlung", betrag, text });
    }

    DB.speichereMitglieder(aktuelleMitglieder);
    DB.speichereKasse(this.kasse);
    this.mitglieder = aktuelleMitglieder;
  }

  rollbackStartgebuehren() {
    if (Object.keys(this.preSessionSchulden).length === 0) return;

    const k = clone(this.kasse);
    for (const tx of [...this.sessionTx].reverse()) {
      if (tx.kind === "einzahlung") k.Kassenstand = Math.max(0, round2(k.Kassenstand - tx.betrag));
      else k.Kassenstand += tx.betrag;
      const idx = k.Transaktionen.lastIndexOf(tx.text);
      if (idx >= 0) k.Transaktionen.splice(idx, 1);
    }
    this.kasse = k;
    DB.speichereKasse(this.kasse);

    const m = DB.ladeMitglieder();
    for (const [name, schuld] of Object.entries(this.preSessionSchulden)) {
      if (m[name]) m[name].offene_zahlung = schuld;
    }
    DB.speichereMitglieder(m);
    this.mitglieder = m;

    this.sessionTx = [];
    this.preSessionSchulden = {};
    this.pendingAttendees = [];
    this.pendingGäste = [];
  }

  spielStarten(orderedNames, gäste) {
    const aktuelleMitglieder = DB.ladeMitglieder();
    const eindeutigeNamen = uniqueNames(orderedNames);
    const eindeutigeGäste = uniquePlayersByName(gäste);

    for (const gast of eindeutigeGäste) {
      const existing = aktuelleMitglieder[gast.name];
      if (existing) {
        // Don't downgrade an existing Stamm-Mitglied to "Gast" just because a
        // guest entry happens to share its name — keep the member record intact.
        if (existing.typ !== "Stamm") existing.typ = "Gast";
      } else {
        aktuelleMitglieder[gast.name] = toPlayerData(gast);
      }
    }
    DB.speichereMitglieder(aktuelleMitglieder);
    this.mitglieder = aktuelleMitglieder;

    this.players = eindeutigeNamen
      .filter((n) => aktuelleMitglieder[n])
      .map((n) => playerFromData(n, aktuelleMitglieder[n]));

    this.runde = 1;
    this._speichereAktuellesSpiel();
    this.kasse.Letzte_Startgebuehren = this.kasse.Startgeld * this.players.length;
    DB.speichereKasse(this.kasse);
    this.gameRunning = true;
    this.abgerechnet = false;
    this.route = null; // mirrors .onChange(of: vm.gameRunning) { selectedItem = nil }
  }

  // ---------------------------------------------------------------- Score updates

  updatePunkte(playerName, runde, wert) {
    const idx = this.players.findIndex((p) => p.name === playerName);
    if (idx < 0) return;
    this.players[idx].punkte[runde] = wert;
    this._speichereAktuellesSpiel();
  }

  updatePumpen(playerName, delta) {
    const idx = this.players.findIndex((p) => p.name === playerName);
    if (idx < 0) return;
    this.players[idx].pumpen = Math.max(0, this.players[idx].pumpen + delta);
    this._speichereAktuellesSpiel();
  }

  updateNeuner(playerName, delta) {
    const idx = this.players.findIndex((p) => p.name === playerName);
    if (idx < 0) return;
    this.players[idx].neuner = Math.max(0, this.players[idx].neuner + delta);
    this._speichereAktuellesSpiel();
  }

  updateKranz(playerName, delta) {
    const idx = this.players.findIndex((p) => p.name === playerName);
    if (idx < 0) return;
    this.players[idx].kranz = Math.max(0, this.players[idx].kranz + delta);
    this._speichereAktuellesSpiel();
  }

  // ---------------------------------------------------------------- Billing & settlement

  get hatRundenpunkte() {
    return this.players.some((p) => p.punkte.some((x) => x > 0));
  }

  /** Returns the sheet name to open ("pumpenStechen" | "tiebreak" | "billing"), or null if the game was aborted. */
  abrechnungStarten() {
    if (!this.hatRundenpunkte) {
      this.spielAbbrechen();
      return null;
    }
    if (this.brauchtPumpenstechen()) return "pumpenStechen";
    if (this.hasTrueTie()) return "tiebreak";
    return "billing";
  }

  berechneBillingRows() {
    const ranking = this.resolveRanking();
    if (this.players.length === 0) return [];
    const rows = [];
    ranking.forEach((player, i) => {
      const myPumpen = player.pumpen + (this.tiebreakExtras[player.name]?.pumpen || 0);
      let fremdeNeuner = 0;
      let fremdeKraenze = 0;
      for (const other of this.players) {
        if (other.name === player.name) continue;
        fremdeNeuner += other.neuner + (this.tiebreakExtras[other.name]?.neuner || 0);
        fremdeKraenze += other.kranz + (this.tiebreakExtras[other.name]?.kranz || 0);
      }
      const pumpenBetrag = myPumpen * this.kasse.Pumpe;
      const neunerBetrag = fremdeNeuner * this.kasse.Neuner;
      const kranzBetrag = fremdeKraenze * this.kasse.Kranz;
      rows.push({
        platz: i + 1,
        player,
        zuZahlen: round2(pumpenBetrag + neunerBetrag + kranzBetrag),
        gezahlt: 0,
        perKarte: false,
        pumpenAnzahl: myPumpen,
        pumpenBetrag: round2(pumpenBetrag),
        fremdeNeuner,
        fremdeNeunerBetrag: round2(neunerBetrag),
        fremdeKraenze,
        fremdeKraenzeBetrag: round2(kranzBetrag),
      });
    });
    return rows;
  }

  resolveRanking() {
    const sorted = [...this.players].sort((a, b) => summe(b) - summe(a));
    const result = [];
    let i = 0;
    while (i < sorted.length) {
      let j = i;
      while (j < sorted.length && summe(sorted[j]) === summe(sorted[i])) j++;
      const gruppe = sorted.slice(i, j);
      if (gruppe.length === 1) {
        result.push(gruppe[0]);
      } else {
        const hasTiebreakData = gruppe.some((p) => this.tiebreakExtras[p.name] !== undefined);
        if (hasTiebreakData) {
          const byTiebreak = [...gruppe].sort(
            (a, b) => (this.tiebreakExtras[b.name]?.punkte || 0) - (this.tiebreakExtras[a.name]?.punkte || 0)
          );
          result.push(...byTiebreak);
        } else if (Object.keys(this.pumpRank).length > 0) {
          const byRank = [...gruppe].sort(
            (a, b) => (this.pumpRank[a.name] ?? Infinity) - (this.pumpRank[b.name] ?? Infinity)
          );
          result.push(...byRank);
        } else {
          const pumpenCounts = gruppe.map((p) => p.pumpen);
          const maxPumpen = Math.max(0, ...pumpenCounts);
          const mitMaxPumpen = gruppe.filter((p) => p.pumpen === maxPumpen);
          if (mitMaxPumpen.length === 1) {
            const rest = gruppe.filter((p) => p.name !== mitMaxPumpen[0].name);
            result.push(...rest, mitMaxPumpen[0]);
          } else {
            result.push(...gruppe);
          }
        }
      }
      i = j;
    }
    return result;
  }

  abrechnungSpeichern(rows) {
    const datum = formatDatum();
    const archiveStartIndex = this.kasse.Transaktionen.length;

    const startgeldInfo = round2(this.kasse.Letzte_Startgebuehren);
    if (startgeldInfo > 0) {
      this._addEinzahlung(startgeldInfo, `Startgelder für ${this.players.length} Spieler`, datum, true);
    }

    let gesamtZahlungen = 0;
    const aktuelleMitglieder = this._aktuelleMitgliederAusState();

    for (const row of rows) {
      const betrag = round2(row.zuZahlen);
      const playerData = aktuelleMitglieder[row.player.name] || toPlayerData(row.player);

      if (betrag > 0) {
        playerData.offene_zahlung = round2(playerData.offene_zahlung + betrag);
        const text = this._addEinzahlung(betrag, `${datum} - Strafe belastet: ${row.player.name}`, datum, true);
        this.sessionTx.push({ kind: "info", betrag: 0, text });
      }

      const gezahlt = Math.max(0, round2(row.gezahlt));
      const zahlungAufSchuld = Math.min(gezahlt, playerData.offene_zahlung);
      if (zahlungAufSchuld > 0) {
        playerData.offene_zahlung = round2(Math.max(0, playerData.offene_zahlung - zahlungAufSchuld));
        const text = row.perKarte
          ? this._addEinzahlungKonto(zahlungAufSchuld, `Zahlung von ${row.player.name} (Karte)`, datum)
          : this._addEinzahlung(zahlungAufSchuld, `${datum} - Zahlung von ${row.player.name}`, datum);
        this.sessionTx.push({ kind: "einzahlung", betrag: zahlungAufSchuld, text });
        gesamtZahlungen += zahlungAufSchuld;
      }

      const spende = round2(Math.max(0, gezahlt - zahlungAufSchuld));
      if (spende > 0) {
        const text = row.perKarte
          ? this._addEinzahlungKonto(spende, `Spende von ${row.player.name} (Karte)`, datum)
          : this._addEinzahlung(spende, `${datum} - Spende von ${row.player.name}`, datum);
        this.sessionTx.push({ kind: "einzahlung", betrag: spende, text });
        gesamtZahlungen += spende;
      }

      aktuelleMitglieder[row.player.name] = playerData;
    }

    if (this.kasse.Bahngebuehr > 0) {
      const text = this._addAuszahlung(this.kasse.Bahngebuehr, `${datum} - Bahngebühr`, datum);
      this.sessionTx.push({ kind: "auszahlung", betrag: this.kasse.Bahngebuehr, text });
    }

    const infoSumme = round2(gesamtZahlungen + startgeldInfo);
    if (infoSumme > 0) {
      this._addEinzahlung(infoSumme, `${datum} - Zahlungen vom Spieltag`, datum, true);
    }

    DB.speichereMitglieder(aktuelleMitglieder);
    this.mitglieder = aktuelleMitglieder;
    DB.speichereKasse(this.kasse);

    const archivePlayers = {};
    for (const player of uniquePlayersByName(this.players)) {
      const data = toPlayerData(player);
      data.offene_zahlung = aktuelleMitglieder[player.name]?.offene_zahlung ?? data.offene_zahlung;
      archivePlayers[player.name] = data;
    }
    const spieltagTransaktionen = this.kasse.Transaktionen.slice(archiveStartIndex);

    try {
      DB.archivierSpiel(datum, archivePlayers, spieltagTransaktionen, uniqueNames(this.players.map((p) => p.name)));
    } catch (e) {
      this.archivFehler = "Spiel konnte nicht archiviert werden: " + e.message;
    }

    // Reset game state
    this.abgerechnet = true;
    this.gameRunning = false;
    this.tiebreakExtras = {};
    this.pumpRank = {};
    this.billingRows = [];
    this.billingGezahlt = {};
    this.sessionTx = [];
    this.preSessionSchulden = {};
    this.pendingAttendees = [];
    this.pendingGäste = [];
    this.players = [];
    this.route = null;

    DB.speichereAktuellesSpiel({ players: {}, runde: 0, abgerechnet: true, spieler_reihenfolge: null });
  }

  // ---------------------------------------------------------------- Abort

  spielAbbrechen() {
    const k = clone(this.kasse);
    for (const tx of [...this.sessionTx].reverse()) {
      if (tx.kind === "einzahlung") k.Kassenstand = Math.max(0, round2(k.Kassenstand - tx.betrag));
      else k.Kassenstand += tx.betrag;
      const idx = k.Transaktionen.lastIndexOf(tx.text);
      if (idx >= 0) k.Transaktionen.splice(idx, 1);
    }
    this.kasse = k;
    DB.speichereKasse(this.kasse);

    const aktuelleMitglieder = DB.ladeMitglieder();
    for (const [name, schuld] of Object.entries(this.preSessionSchulden)) {
      if (aktuelleMitglieder[name]) aktuelleMitglieder[name].offene_zahlung = schuld;
    }
    DB.speichereMitglieder(aktuelleMitglieder);
    this.mitglieder = aktuelleMitglieder;

    this.sessionTx = [];
    this.preSessionSchulden = {};
    this.billingRows = [];
    this.billingGezahlt = {};
    this.tiebreakExtras = {};
    this.pumpRank = {};
    this.pendingAttendees = [];
    this.pendingGäste = [];
    this.players = [];
    this.gameRunning = false;
    this.route = null;

    DB.speichereAktuellesSpiel({ players: {}, runde: 0, abgerechnet: false, spieler_reihenfolge: null });
  }

  // ---------------------------------------------------------------- Cash management

  einzahlen(betrag, beschreibung, spielerName = null, konto = false) {
    if (!(betrag > 0)) return;
    if (konto) this._addEinzahlungKonto(betrag, beschreibung);
    else this._addEinzahlung(betrag, beschreibung);

    if (spielerName) {
      const m = DB.ladeMitglieder();
      if (m[spielerName]) {
        m[spielerName].offene_zahlung = Math.max(0, round2(m[spielerName].offene_zahlung - betrag));
      }
      DB.speichereMitglieder(m);
      this.mitglieder = m;
    }
    DB.speichereKasse(this.kasse);
  }

  auszahlen(betrag, beschreibung, konto = false) {
    const balance = konto ? this.kasse.Kontostand : this.kasse.Kassenstand;
    if (!(betrag > 0) || betrag > balance) return;
    if (konto) this._addAuszahlungKonto(betrag, beschreibung);
    else this._addAuszahlung(betrag, beschreibung);
    DB.speichereKasse(this.kasse);
  }

  umbuchenBarZuKonto(betrag) {
    if (!(betrag > 0) || betrag > this.kasse.Kassenstand) return;
    const wert = round2(betrag);
    const d = formatDatum();
    this.kasse.Kassenstand = Math.max(0, round2(this.kasse.Kassenstand - wert));
    this.kasse.Kontostand = round2(this.kasse.Kontostand + wert);
    this.kasse.Transaktionen.push(`${d} | Umbuchung Bar → Konto: ${wert.toFixed(2)}€`);
    DB.speichereKasse(this.kasse);
  }

  umbuchenKontoZuBar(betrag) {
    if (!(betrag > 0) || betrag > this.kasse.Kontostand) return;
    const wert = round2(betrag);
    const d = formatDatum();
    this.kasse.Kontostand = Math.max(0, round2(this.kasse.Kontostand - wert));
    this.kasse.Kassenstand = round2(this.kasse.Kassenstand + wert);
    this.kasse.Transaktionen.push(`${d} | Umbuchung Konto → Bar: +${wert.toFixed(2)}€`);
    DB.speichereKasse(this.kasse);
  }

  // ---------------------------------------------------------------- Player management

  spielerHinzufügen(name, typ, offeneZahlung, vollname = "") {
    const updated = clone(this._aktuelleMitgliederAusState());
    if (this._playerNameExists(name, updated)) return;
    const pd = defaultPlayerData(typ);
    pd.offene_zahlung = offeneZahlung;
    pd.vollname = vollname;
    updated[name] = pd;
    this.mitglieder = updated;
    DB.speichereMitglieder(updated);
  }

  spielerBearbeiten(alterName, neuerName, typ, offeneZahlung, vollname = "") {
    const updated = clone(this._aktuelleMitgliederAusState());
    if (!namesEqual(alterName, neuerName) && this._playerNameExists(neuerName, updated)) return;
    const pd = updated[alterName] || defaultPlayerData(typ);
    pd.typ = typ;
    pd.offene_zahlung = offeneZahlung;
    pd.vollname = vollname;
    if (alterName !== neuerName) delete updated[alterName];
    updated[neuerName] = pd;
    this.mitglieder = updated;
    DB.speichereMitglieder(updated);
  }

  spielerLöschen(name) {
    const updated = clone(this._aktuelleMitgliederAusState());
    const key = Object.keys(updated).find((k) => namesEqual(k, name));
    if (key) delete updated[key];
    this.mitglieder = updated;
    DB.speichereMitglieder(updated);
  }

  // ---------------------------------------------------------------- Tiebreak

  hasTrueTie() {
    return this.getTiedPlayers().length > 0;
  }

  getTiedPlayers() {
    const sorted = [...this.players].sort((a, b) => summe(b) - summe(a));
    if (sorted.length < 2) return [];
    let i = 0;
    while (i < sorted.length) {
      let j = i;
      while (j < sorted.length && summe(sorted[j]) === summe(sorted[i])) j++;
      const gruppe = sorted.slice(i, j);
      if (gruppe.length >= 2) {
        const tiebreakPunkte = gruppe.map((p) => this.tiebreakExtras[p.name]?.punkte || 0);
        if (new Set(tiebreakPunkte).size > 1) {
          i = j;
          continue;
        }
        return gruppe.map((p) => p.name);
      }
      i = j;
    }
    return [];
  }

  addTiebreakStats(name, pumpen, neuner, kranz, punkte) {
    const extra = this.tiebreakExtras[name] || { pumpen: 0, neuner: 0, kranz: 0, punkte: 0 };
    extra.pumpen += pumpen;
    extra.neuner += neuner;
    extra.kranz += kranz;
    extra.punkte += punkte;
    this.tiebreakExtras[name] = extra;
  }

  brauchtPumpenstechen() {
    if (Object.keys(this.pumpRank).length > 0) return false;
    const max = Math.max(0, ...this.players.map((p) => p.pumpen));
    if (max <= 0) return false;
    return this.players.filter((p) => p.pumpen === max).length > 1;
  }

  getPumpTiedPlayers() {
    const max = Math.max(0, ...this.players.map((p) => p.pumpen));
    if (max <= 0) return [];
    return this.players
      .filter((p) => p.pumpen === max)
      .map((p) => p.name)
      .sort();
  }

  setPumpRank(ordered) {
    this.pumpRank = {};
    ordered.forEach((name, i) => (this.pumpRank[name] = i));
  }

  // ---------------------------------------------------------------- Settings

  einstellungenSpeichern(neueKasse) {
    this.kasse = neueKasse;
    DB.speichereKasse(this.kasse);
  }

  // ---------------------------------------------------------------- Helpers

  _speichereAktuellesSpiel() {
    const dict = {};
    for (const p of uniquePlayersByName(this.players)) dict[p.name] = toPlayerData(p);
    DB.speichereAktuellesSpiel({
      players: dict,
      runde: this.runde,
      abgerechnet: this.abgerechnet,
      spieler_reihenfolge: uniqueNames(this.players.map((p) => p.name)),
    });
  }

  _aktuelleMitgliederAusState() {
    if (Object.keys(this.mitglieder).length > 0) return this.mitglieder;
    return DB.ladeMitglieder();
  }

  _playerNameExists(name, players) {
    return Object.keys(players).some((k) => namesEqual(k, name));
  }

  _addEinzahlung(betrag, beschreibung, datum = null, infoOnly = false) {
    const wert = round2(betrag);
    const d = datum || formatDatum();
    let text;
    if (infoOnly) {
      text = `${d} | ${wert.toFixed(2)}€: ${beschreibung}`;
    } else {
      this.kasse.Kassenstand = round2(this.kasse.Kassenstand + wert);
      text = `${d} | +${wert.toFixed(2)}€: ${beschreibung}`;
    }
    this.kasse.Transaktionen.push(text);
    return text;
  }

  _addAuszahlung(betrag, beschreibung, datum = null) {
    const wert = round2(betrag);
    const d = datum || formatDatum();
    this.kasse.Kassenstand = Math.max(0, round2(this.kasse.Kassenstand - wert));
    const text = `${d} | -${wert.toFixed(2)}€: ${beschreibung}`;
    this.kasse.Transaktionen.push(text);
    return text;
  }

  _addEinzahlungKonto(betrag, beschreibung, datum = null) {
    const wert = round2(betrag);
    const d = datum || formatDatum();
    this.kasse.Kontostand = round2(this.kasse.Kontostand + wert);
    const text = `[Konto] ${d} | +${wert.toFixed(2)}€: ${beschreibung}`;
    this.kasse.Transaktionen.push(text);
    return text;
  }

  _addAuszahlungKonto(betrag, beschreibung) {
    const wert = round2(betrag);
    const d = formatDatum();
    this.kasse.Kontostand = Math.max(0, round2(this.kasse.Kontostand - wert));
    const text = `[Konto] ${d} | -${wert.toFixed(2)}€: ${beschreibung}`;
    this.kasse.Transaktionen.push(text);
    return text;
  }

  get letzterSpieltag() {
    const historic = DB.ladeHistorie();
    if (historic.length > 0) {
      const last = historic[historic.length - 1];
      return last.spieler_reihenfolge || Object.keys(last.players).sort();
    }
    return [];
  }
}

// Factory instead of an eagerly-created singleton: the Store constructor
// reads from DB.* synchronously, so DB.init() (async — loads sql.js +
// IndexedDB) must resolve first. main.js awaits that, then calls this.
export function createVm() {
  return new Store();
}
export { newPlayer, summe, namesEqual, uniqueNames, uniquePlayersByName, toPlayerData, playerFromData };
