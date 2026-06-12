import Foundation
import SwiftUI

@MainActor
class AppViewModel: ObservableObject {

    let store = DataStore.shared

    // MARK: - Persistent state
    @Published var kasse: KasseFile = KasseFile.defaultValue
    @Published var mitglieder: [String: PlayerData] = [:]

    // MARK: - Game session state
    @Published var players: [Player] = []          // active players this game (in order)
    @Published var runde: Int = 0
    @Published var abgerechnet: Bool = false
    @Published var gameRunning: Bool = false

    // MARK: - Billing state
    @Published var billingRows: [BillingRow] = []
    @Published var tiebreakExtras: [String: TiebreakExtra] = [:]
    @Published var pumpRank: [String: Int] = [:]  // rank 0 = winner of Pumpenstechen

    // MARK: - Session rollback
    private var sessionTx: [(kind: String, betrag: Double, text: String)] = []
    private var preSessionSchulden: [String: Double] = [:]

    // MARK: - Attendance flow temp state
    @Published var pendingAttendees: [String] = []
    @Published var pendingGäste: [Player] = []

    // MARK: - Error state
    @Published var archivFehler: String? = nil

    // MARK: - Navigation state
    @Published var activeSheet: AppSheet? = nil
    @Published var showLockWarning: Bool = false
    @Published var lockWarningMessage: String = ""
    @Published var lockWarningGerät: String = ""
    @Published var lockWarningSeit: String = ""
    @Published var onLockOverride: (() -> Void)? = nil

    enum AppSheet: Identifiable {
        case attendance, playerSort, game, billing, cash, players, settings, archive, tiebreak, pumpenStechen
        var id: String { "\(self)" }
    }

    // MARK: - Load on start

    func laden() {
        guard store.isDatabaseOpen else {
            print("Laden übersprungen: SQLite nicht geöffnet")
            return
        }
        kasse = store.ladeKasse()
        mitglieder = store.ladeMitglieder().players
        ladeAktuellesSpiel()
    }

    private func ladeAktuellesSpiel() {
        let spiel = store.ladeAktuellesSpiel()
        abgerechnet = spiel.abgerechnet
        let order = spiel.spieler_reihenfolge ?? Array(spiel.players.keys).sorted()
        players = order.compactMap { name in
            spiel.players[name].map { Player(name: name, data: $0) }
        }
        gameRunning = !spiel.players.isEmpty
    }

    // MARK: - Lock handling

    func prüfeLockUndStarte(onSuccess: @escaping () -> Void) {
        guard let lock = store.ladeLock() else {
            store.setzeLock()
            onSuccess()
            return
        }

        if store.lockIstAbgelaufen(lock) {
            store.setzeLock()
            onSuccess()
            return
        }

        let formatter = ISO8601DateFormatter()
        let seit: String
        if let date = formatter.date(from: lock.seit) {
            let df = DateFormatter()
            df.dateFormat = "dd.MM.yyyy HH:mm 'Uhr'"
            seit = df.string(from: date)
        } else {
            seit = lock.seit
        }

        lockWarningGerät = lock.gerät
        lockWarningSeit = seit
        onLockOverride = {
            self.store.setzeLock()
            onSuccess()
        }
        showLockWarning = true
    }

    func lockFreigeben() {
        store.loescheLock()
    }

    // MARK: - New game flow

    func starteNeuesSpiel() {
        guard !gameRunning else { return }
        laden()
        guard !mitglieder.isEmpty else {
            print("Neues Spiel abgebrochen: Keine Spieler vorhanden")
            return
        }
        sessionTx = []
        preSessionSchulden = [:]
        pendingAttendees = []
        pendingGäste = []
        tiebreakExtras = [:]
        pumpRank = [:]
        runde = 1
        abgerechnet = false
        activeSheet = .attendance
    }

    // MARK: - Attendance

    func berechneStartgebuehren(anwesend: [String: Bool], zahlungen: [String: Double]) {
        preSessionSchulden = [:]
        var aktuelleMitglieder = store.ladeMitglieder()

        for (name, player) in aktuelleMitglieder.players {
            preSessionSchulden[name] = player.offene_zahlung
        }

        for (name, istAnwesend) in anwesend {
            guard var playerData = aktuelleMitglieder.players[name] else { continue }
            if istAnwesend {
                playerData.offene_zahlung += kasse.Startgeld
            } else {
                playerData.offene_zahlung += kasse.Strafe_Stamm
            }
            aktuelleMitglieder.players[name] = playerData
        }

        for (name, betrag) in zahlungen where betrag > 0 {
            if var pd = aktuelleMitglieder.players[name] {
                let datum = formatDatum(Date())
                let beschreibung = betrag >= pd.offene_zahlung
                    ? "Zahlung von \(name)"
                    : "Teilzahlung von \(name)"
                pd.offene_zahlung = max(0, pd.offene_zahlung - betrag)
                aktuelleMitglieder.players[name] = pd
                let text = addEinzahlung(betrag: betrag, beschreibung: beschreibung, datum: datum)
                sessionTx.append((kind: "einzahlung", betrag: betrag, text: text))
            }
        }

        store.speichereMitglieder(aktuelleMitglieder)
        store.speichereKasse(kasse)
        mitglieder = aktuelleMitglieder.players
    }

    // Rollback start fees when navigating back from PlayerSortView to AttendanceView
    func rollbackStartgebuehren() {
        guard !preSessionSchulden.isEmpty else { return }

        var aktualisierteKasse = kasse
        for tx in sessionTx.reversed() {
            if tx.kind == "einzahlung" {
                aktualisierteKasse.Kassenstand = max(0, aktualisierteKasse.Kassenstand - tx.betrag)
            } else {
                aktualisierteKasse.Kassenstand += tx.betrag
            }
            if let idx = aktualisierteKasse.Transaktionen.lastIndex(of: tx.text) {
                aktualisierteKasse.Transaktionen.remove(at: idx)
            }
        }
        kasse = aktualisierteKasse
        store.speichereKasse(kasse)

        var m = store.ladeMitglieder()
        for (name, schuld) in preSessionSchulden {
            if var p = m.players[name] {
                p.offene_zahlung = schuld
                m.players[name] = p
            }
        }
        store.speichereMitglieder(m)
        mitglieder = m.players

        sessionTx = []
        preSessionSchulden = [:]
        pendingAttendees = []
        pendingGäste = []
    }

    // Called after sort – start actual game
    func spielStarten(orderedNames: [String], gäste: [Player]) {
        var aktuelleMitglieder = store.ladeMitglieder()
        let eindeutigeNamen  = uniqueNames(orderedNames)
        let eindeutigeGäste  = uniquePlayersByName(gäste)

        // Add guests, preserving fees/payments already recorded during attendance
        for gast in eindeutigeGäste {
            if var existing = aktuelleMitglieder.players[gast.name] {
                existing.typ = "Gast"
                aktuelleMitglieder.players[gast.name] = existing
            } else {
                aktuelleMitglieder.players[gast.name] = gast.toPlayerData()
            }
        }
        store.speichereMitglieder(aktuelleMitglieder)
        mitglieder = aktuelleMitglieder.players

        players = eindeutigeNamen.compactMap { name in
            aktuelleMitglieder.players[name].map { Player(name: name, data: $0) }
        }

        runde = 1
        speichereAktuellesSpiel()
        kasse.Letzte_Startgebuehren = kasse.Startgeld * Double(players.count)
        store.speichereKasse(kasse)
        gameRunning = true
        abgerechnet = false
        activeSheet = nil
    }

    // MARK: - Score update

    func updatePunkte(playerName: String, runde: Int, wert: Int) {
        guard let idx = players.firstIndex(where: { $0.name == playerName }) else { return }
        players[idx].punkte[runde] = wert
        speichereAktuellesSpiel()
    }

    func updatePumpen(playerName: String, delta: Int) {
        guard let idx = players.firstIndex(where: { $0.name == playerName }) else { return }
        players[idx].pumpen = max(0, players[idx].pumpen + delta)
        speichereAktuellesSpiel()
    }

    func updateNeuner(playerName: String, delta: Int) {
        guard let idx = players.firstIndex(where: { $0.name == playerName }) else { return }
        players[idx].neuner = max(0, players[idx].neuner + delta)
        speichereAktuellesSpiel()
    }

    func updateKranz(playerName: String, delta: Int) {
        guard let idx = players.firstIndex(where: { $0.name == playerName }) else { return }
        players[idx].kranz = max(0, players[idx].kranz + delta)
        speichereAktuellesSpiel()
    }

    // MARK: - Billing & Settlement

    func abrechnungStarten() {
        guard hatRundenpunkte else {
            spielAbbrechen()
            return
        }
        if brauchtPumpenstechen() {
            activeSheet = .pumpenStechen
        } else if hasTrueTie() {
            activeSheet = .tiebreak
        } else {
            activeSheet = .billing
        }
    }

    var hatRundenpunkte: Bool {
        players.contains { player in
            player.punkte.contains { $0 > 0 }
        }
    }

    func berechneBillingRows() -> [BillingRow] {
        let ranking = resolveRanking()
        guard !players.isEmpty else { return [] }

        var rows: [BillingRow] = []
        for (platz, player) in ranking.enumerated() {
            let myPumpen = player.pumpen + (tiebreakExtras[player.name]?.pumpen ?? 0)
            var fremdeNeuner = 0
            var fremdeKraenze = 0
            for other in players where other.name != player.name {
                fremdeNeuner  += other.neuner + (tiebreakExtras[other.name]?.neuner ?? 0)
                fremdeKraenze += other.kranz  + (tiebreakExtras[other.name]?.kranz  ?? 0)
            }
            let pumpenBetrag = Double(myPumpen) * kasse.Pumpe
            let neunerBetrag = Double(fremdeNeuner) * kasse.Neuner
            let kranzBetrag  = Double(fremdeKraenze) * kasse.Kranz
            rows.append(BillingRow(
                platz: platz + 1,
                player: player,
                zuZahlen: round2(pumpenBetrag + neunerBetrag + kranzBetrag),
                pumpenAnzahl: myPumpen,
                pumpenBetrag: round2(pumpenBetrag),
                fremdeNeuner: fremdeNeuner,
                fremdeNeunerBetrag: round2(neunerBetrag),
                fremdeKraenze: fremdeKraenze,
                fremdeKraenzeBetrag: round2(kranzBetrag)
            ))
        }
        return rows
    }

    func resolveRanking() -> [Player] {
        let sorted = players.sorted { $0.summe > $1.summe }
        var result: [Player] = []
        var i = 0
        while i < sorted.count {
            var j = i
            while j < sorted.count && sorted[j].summe == sorted[i].summe { j += 1 }
            let gruppe = Array(sorted[i..<j])
            if gruppe.count == 1 {
                result.append(gruppe[0])
            } else {
                // If a tiebreak was played for this group, tiebreak punkte take full precedence.
                // Using pumpen here would penalise the tiebreak winner for gutters scored
                // during the tiebreak round itself.
                let hasTiebreakData = gruppe.contains { tiebreakExtras[$0.name] != nil }
                if hasTiebreakData {
                    let byTiebreak = gruppe.sorted {
                        (tiebreakExtras[$0.name]?.punkte ?? 0) > (tiebreakExtras[$1.name]?.punkte ?? 0)
                    }
                    result.append(contentsOf: byTiebreak)
                } else if !pumpRank.isEmpty {
                    // Pumpenstechen was resolved: sort by pump rank (lower = better position)
                    let byRank = gruppe.sorted { (pumpRank[$0.name] ?? Int.max) < (pumpRank[$1.name] ?? Int.max) }
                    result.append(contentsOf: byRank)
                } else {
                    // Normal pumpen tiebreak (most pumpen → worst rank)
                    let pumpenCounts = gruppe.map { $0.pumpen }
                    let maxPumpen = pumpenCounts.max() ?? 0
                    let mitMaxPumpen = gruppe.filter { $0.pumpen == maxPumpen }
                    if mitMaxPumpen.count == 1 {
                        let rest = gruppe.filter { $0.name != mitMaxPumpen[0].name }
                        result.append(contentsOf: rest)
                        result.append(mitMaxPumpen[0])
                    } else {
                        result.append(contentsOf: gruppe)
                    }
                }
            }
            i = j
        }
        return result
    }

    func abrechnungSpeichern(rows: [BillingRow]) {
        let datum = formatDatum(Date())
        let archiveStartIndex = kasse.Transaktionen.count

        let startgeldInfo = round2(kasse.Letzte_Startgebuehren)
        if startgeldInfo > 0 {
            _ = addEinzahlung(
                betrag: startgeldInfo,
                beschreibung: "Startgelder für \(players.count) Spieler",
                datum: datum,
                infoOnly: true
            )
        }

        var gesamtZahlungen = 0.0
        var aktuelleMitglieder = aktuelleMitgliederAusState()

        for row in rows {
            let betrag = round2(row.zuZahlen)
            var playerData = aktuelleMitglieder.players[row.player.name] ?? row.player.toPlayerData()

            if betrag > 0 {
                playerData.offene_zahlung = round2(playerData.offene_zahlung + betrag)
                let text = addEinzahlung(
                    betrag: betrag,
                    beschreibung: "\(datum) - Strafe belastet: \(row.player.name)",
                    datum: datum,
                    infoOnly: true
                )
                sessionTx.append((kind: "info", betrag: 0, text: text))
            }

            let gezahlt = max(0, round2(row.gezahlt))
            let zahlungAufSchuld = min(gezahlt, playerData.offene_zahlung)
            if zahlungAufSchuld > 0 {
                playerData.offene_zahlung = round2(max(0, playerData.offene_zahlung - zahlungAufSchuld))
                let text = addEinzahlung(
                    betrag: zahlungAufSchuld,
                    beschreibung: "\(datum) - Zahlung von \(row.player.name)",
                    datum: datum
                )
                sessionTx.append((kind: "einzahlung", betrag: zahlungAufSchuld, text: text))
                gesamtZahlungen += zahlungAufSchuld
            }

            let spende = round2(max(0, gezahlt - zahlungAufSchuld))
            if spende > 0 {
                let text = addEinzahlung(
                    betrag: spende,
                    beschreibung: "\(datum) - Spende von \(row.player.name)",
                    datum: datum
                )
                sessionTx.append((kind: "einzahlung", betrag: spende, text: text))
                gesamtZahlungen += spende
            }

            aktuelleMitglieder.players[row.player.name] = playerData
        }

        if kasse.Bahngebuehr > 0 {
            let text = addAuszahlung(
                betrag: kasse.Bahngebuehr,
                beschreibung: "\(datum) - Bahngebühr",
                datum: datum
            )
            sessionTx.append((kind: "auszahlung", betrag: kasse.Bahngebuehr, text: text))
        }

        let infoSumme = round2(gesamtZahlungen + startgeldInfo)
        if infoSumme > 0 {
            _ = addEinzahlung(
                betrag: infoSumme,
                beschreibung: "\(datum) - Zahlungen vom Spieltag",
                datum: datum,
                infoOnly: true
            )
        }

        store.speichereMitglieder(aktuelleMitglieder)
        mitglieder = aktuelleMitglieder.players
        store.speichereKasse(kasse)

        let archivePlayers = Dictionary(uniqueKeysWithValues: uniquePlayersByName(players).map { player in
            var data = player.toPlayerData()
            data.offene_zahlung = aktuelleMitglieder.players[player.name]?.offene_zahlung ?? data.offene_zahlung
            return (player.name, data)
        })
        let spieltagTransaktionen = Array(kasse.Transaktionen.dropFirst(archiveStartIndex))

        do {
            try store.archivierSpiel(
                datum: datum,
                players: archivePlayers,
                transaktionen: spieltagTransaktionen,
                reihenfolge: uniqueNames(players.map { $0.name })
            )
        } catch {
            archivFehler = "Spiel konnte nicht archiviert werden: \(error.localizedDescription)"
        }

        // Reset game state
        abgerechnet = true
        gameRunning = false
        tiebreakExtras = [:]
        pumpRank = [:]
        sessionTx = []
        preSessionSchulden = [:]
        pendingAttendees = []
        pendingGäste = []
        players = []
        activeSheet = nil

        let emptySpiel = AktuellesSpielFile(
            players: [:], runde: 0, abgerechnet: true, spieler_reihenfolge: nil
        )
        store.speichereAktuellesSpiel(emptySpiel)
    }

    // MARK: - Game abort (Rollback)

    func spielAbbrechen() {
        var aktualisierteKasse = kasse
        for tx in sessionTx.reversed() {
            if tx.kind == "einzahlung" {
                aktualisierteKasse.Kassenstand = max(0, aktualisierteKasse.Kassenstand - tx.betrag)
            } else {
                aktualisierteKasse.Kassenstand += tx.betrag
            }
            if let idx = aktualisierteKasse.Transaktionen.lastIndex(of: tx.text) {
                aktualisierteKasse.Transaktionen.remove(at: idx)
            }
        }
        kasse = aktualisierteKasse
        store.speichereKasse(kasse)

        var aktuelleMitglieder = store.ladeMitglieder()
        for (name, schuld) in preSessionSchulden {
            if var p = aktuelleMitglieder.players[name] {
                p.offene_zahlung = schuld
                aktuelleMitglieder.players[name] = p
            }
        }
        store.speichereMitglieder(aktuelleMitglieder)
        mitglieder = aktuelleMitglieder.players

        sessionTx = []
        preSessionSchulden = [:]
        tiebreakExtras = [:]
        pumpRank = [:]
        pendingAttendees = []
        pendingGäste = []
        players = []
        gameRunning = false
        activeSheet = nil

        let empty = AktuellesSpielFile(players: [:], runde: 0, abgerechnet: false, spieler_reihenfolge: nil)
        store.speichereAktuellesSpiel(empty)
    }

    // MARK: - Cash management

    func einzahlen(betrag: Double, beschreibung: String, spielerName: String? = nil, konto: Bool = false) {
        guard betrag > 0 else { return }
        _ = konto
            ? addEinzahlungKonto(betrag: betrag, beschreibung: beschreibung)
            : addEinzahlung(betrag: betrag, beschreibung: beschreibung)

        if let name = spielerName {
            var m = store.ladeMitglieder()
            if var player = m.players[name] {
                player.offene_zahlung = max(0, player.offene_zahlung - betrag)
                m.players[name] = player
            }
            store.speichereMitglieder(m)
            mitglieder = m.players
        }
        store.speichereKasse(kasse)
    }

    func auszahlen(betrag: Double, beschreibung: String, konto: Bool = false) {
        let balance = konto ? kasse.Kontostand : kasse.Kassenstand
        guard betrag > 0, betrag <= balance else { return }
        _ = konto
            ? addAuszahlungKonto(betrag: betrag, beschreibung: beschreibung)
            : addAuszahlung(betrag: betrag, beschreibung: beschreibung)
        store.speichereKasse(kasse)
    }

    func umbuchenBarZuKonto(betrag: Double) {
        guard betrag > 0, betrag <= kasse.Kassenstand else { return }
        let wert = round2(betrag)
        let d = formatDatum(Date())
        kasse.Kassenstand = max(0, kasse.Kassenstand - wert)
        kasse.Kontostand += wert
        kasse.Transaktionen.append("\(d) | Umbuchung Bar → Konto: \(String(format: "%.2f", wert))€")
        store.speichereKasse(kasse)
    }

    func umbuchenKontoZuBar(betrag: Double) {
        guard betrag > 0, betrag <= kasse.Kontostand else { return }
        let wert = round2(betrag)
        let d = formatDatum(Date())
        kasse.Kontostand = max(0, kasse.Kontostand - wert)
        kasse.Kassenstand += wert
        kasse.Transaktionen.append("\(d) | Umbuchung Konto → Bar: +\(String(format: "%.2f", wert))€")
        store.speichereKasse(kasse)
    }

    // MARK: - Player management

    func spielerHinzufügen(name: String, typ: String, offeneZahlung: Double) {
        var updated = aktuelleMitgliederAusState().players
        guard !playerNameExists(name, in: updated) else { return }
        var pd = PlayerData(typ: typ)
        pd.offene_zahlung = offeneZahlung
        updated[name] = pd
        mitglieder = updated
        store.speichereMitglieder(MitgliederFile(players: updated))
    }

    func spielerBearbeiten(alterName: String, neuerName: String, typ: String, offeneZahlung: Double) {
        var updated = aktuelleMitgliederAusState().players
        guard namesEqual(alterName, neuerName) || !playerNameExists(neuerName, in: updated) else { return }
        var pd = updated[alterName] ?? PlayerData(typ: typ)
        pd.typ = typ
        pd.offene_zahlung = offeneZahlung
        if alterName != neuerName { updated.removeValue(forKey: alterName) }
        updated[neuerName] = pd
        mitglieder = updated
        store.speichereMitglieder(MitgliederFile(players: updated))
    }

    func spielerLöschen(name: String) {
        var updated = aktuelleMitgliederAusState().players
        if let key = updated.keys.first(where: { namesEqual($0, name) }) {
            updated.removeValue(forKey: key)
        }
        mitglieder = updated
        store.speichereMitglieder(MitgliederFile(players: updated))
    }

    // MARK: - Tiebreak

    func hasTrueTie() -> Bool { !getTiedPlayers().isEmpty }

    func getTiedPlayers() -> [String] {
        let sorted = players.sorted { $0.summe > $1.summe }
        guard sorted.count >= 2 else { return [] }

        var i = 0
        while i < sorted.count {
            var j = i
            while j < sorted.count && sorted[j].summe == sorted[i].summe { j += 1 }
            let gruppe = Array(sorted[i..<j])
            if gruppe.count >= 2 {
                // Resolved by Punktestechen punkte (tiebreakExtras is only written
                // by TiebreakView — PumpenTiebreakView uses its own local state).
                let tiebreakPunkte = gruppe.map { tiebreakExtras[$0.name]?.punkte ?? 0 }
                if Set(tiebreakPunkte).count > 1 { i = j; continue }

                // Any unresolved summe-tie → Punktestechen, regardless of pumpen.
                // Pumpen is NOT an automatic substitute for the Stechen.
                return gruppe.map { $0.name }
            }
            i = j
        }
        return []
    }

    func addTiebreakStats(name: String, pumpen: Int, neuner: Int, kranz: Int, punkte: Int) {
        var extra = tiebreakExtras[name] ?? TiebreakExtra()
        extra.pumpen += pumpen
        extra.neuner += neuner
        extra.kranz  += kranz
        extra.punkte += punkte
        tiebreakExtras[name] = extra
    }

    // True when multiple players share the globally highest pumpen count (uses base game count only)
    func brauchtPumpenstechen() -> Bool {
        guard pumpRank.isEmpty else { return false }
        let max = players.map { $0.pumpen }.max() ?? 0
        guard max > 0 else { return false }
        return players.filter { $0.pumpen == max }.count > 1
    }

    func getPumpTiedPlayers() -> [String] {
        let max = players.map { $0.pumpen }.max() ?? 0
        guard max > 0 else { return [] }
        return players.filter { $0.pumpen == max }.map { $0.name }.sorted()
    }

    // Called from PumpenTiebreakView with the stechen result in descending order (winner first)
    func setPumpRank(ordered: [String]) {
        pumpRank = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1, $0) })
    }

    // MARK: - Settings

    func einstellungenSpeichern(_ neueKasse: KasseFile) {
        kasse = neueKasse
        store.speichereKasse(kasse)
    }

    // MARK: - Helpers

    private func speichereAktuellesSpiel() {
        let dict = Dictionary(uniqueKeysWithValues: uniquePlayersByName(players).map { ($0.name, $0.toPlayerData()) })
        let spiel = AktuellesSpielFile(
            players: dict,
            runde: runde,
            abgerechnet: abgerechnet,
            spieler_reihenfolge: uniqueNames(players.map { $0.name })
        )
        store.speichereAktuellesSpiel(spiel)
    }

    private func aktuelleMitgliederAusState() -> MitgliederFile {
        if !mitglieder.isEmpty {
            return MitgliederFile(players: mitglieder)
        }
        return store.ladeMitglieder()
    }

    func formatDatum(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "dd.MM.yyyy"
        return df.string(from: date)
    }

    private func round2(_ val: Double) -> Double {
        let decimal = Decimal(val)
        var rounded = Decimal()
        var mutable = decimal
        NSDecimalRound(&rounded, &mutable, 2, .plain)
        return NSDecimalNumber(decimal: rounded).doubleValue
    }

    private func uniqueNames(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for name in names {
            let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(name)
        }
        return result
    }

    private func uniquePlayersByName(_ players: [Player]) -> [Player] {
        var seen: Set<String> = []
        var result: [Player] = []
        for player in players {
            let key = player.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(player)
        }
        return result
    }

    private func playerNameExists(_ name: String, in players: [String: PlayerData]) -> Bool {
        players.keys.contains { namesEqual($0, name) }
    }

    private func namesEqual(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    @discardableResult
    private func addEinzahlung(
        betrag: Double,
        beschreibung: String,
        datum: String? = nil,
        infoOnly: Bool = false
    ) -> String {
        let wert = round2(betrag)
        let d = datum ?? formatDatum(Date())
        let text: String
        if infoOnly {
            text = "\(d) | \(String(format: "%.2f", wert))€: \(beschreibung)"
        } else {
            kasse.Kassenstand += wert
            text = "\(d) | +\(String(format: "%.2f", wert))€: \(beschreibung)"
        }
        kasse.Transaktionen.append(text)
        return text
    }

    @discardableResult
    private func addAuszahlung(
        betrag: Double,
        beschreibung: String,
        datum: String? = nil
    ) -> String {
        let wert = round2(betrag)
        let d = datum ?? formatDatum(Date())
        kasse.Kassenstand = max(0, kasse.Kassenstand - wert)
        let text = "\(d) | -\(String(format: "%.2f", wert))€: \(beschreibung)"
        kasse.Transaktionen.append(text)
        return text
    }

    @discardableResult
    private func addEinzahlungKonto(betrag: Double, beschreibung: String) -> String {
        let wert = round2(betrag)
        let d = formatDatum(Date())
        kasse.Kontostand += wert
        let text = "[Konto] \(d) | +\(String(format: "%.2f", wert))€: \(beschreibung)"
        kasse.Transaktionen.append(text)
        return text
    }

    @discardableResult
    private func addAuszahlungKonto(betrag: Double, beschreibung: String) -> String {
        let wert = round2(betrag)
        let d = formatDatum(Date())
        kasse.Kontostand = max(0, kasse.Kontostand - wert)
        let text = "[Konto] \(d) | -\(String(format: "%.2f", wert))€: \(beschreibung)"
        kasse.Transaktionen.append(text)
        return text
    }

    var letzterSpieltag: [String] {
        let historic = store.ladeHistorie()
        if let last = historic.last {
            return last.spieler_reihenfolge ?? Array(last.players.keys).sorted()
        }
        return []
    }
}
