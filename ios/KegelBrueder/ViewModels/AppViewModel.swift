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

    // MARK: - Session rollback
    private var sessionTx: [(kind: String, betrag: Double, text: String)] = []
    private var preSessionSchulden: [String: Double] = [:]

    // MARK: - Attendance flow temp state
    @Published var pendingAttendees: [String] = []
    @Published var pendingGäste: [Player] = []

    // MARK: - Navigation state
    @Published var activeSheet: AppSheet? = nil
    @Published var showLockWarning: Bool = false
    @Published var lockWarningMessage: String = ""
    @Published var lockWarningGerät: String = ""
    @Published var lockWarningSeit: String = ""
    @Published var onLockOverride: (() -> Void)? = nil

    enum AppSheet: Identifiable {
        case attendance, playerSort, game, billing, cash, players, settings, archive, tiebreak
        var id: String { "\(self)" }
    }

    // MARK: - Load on start

    func laden() {
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

        // Aktiver Lock – Benutzer fragen
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
        activeSheet = .attendance
    }

    // MARK: - Attendance

    func berechneStartgebuehren(anwesend: [String: Bool], zahlungen: [String: Double]) {
        preSessionSchulden = [:]
        var aktuelleMitglieder = store.ladeMitglieder()

        for (name, player) in aktuelleMitglieder.players where player.typ == "Stamm" {
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

        // Zahlungen verbuchen
        for (name, betrag) in zahlungen where betrag > 0 {
            if var pd = aktuelleMitglieder.players[name] {
                let datum = formatDatum(Date())
                let beschreibung = betrag >= pd.offene_zahlung
                    ? "Zahlung von \(name)"
                    : "Teilzahlung von \(name)"
                pd.offene_zahlung = max(0, pd.offene_zahlung - betrag)
                aktuelleMitglieder.players[name] = pd
                let text = "\(datum) | +\(String(format: "%.2f", betrag))€: \(beschreibung)"
                kasse.Kassenstand += betrag
                kasse.Transaktionen.append(text)
                sessionTx.append((kind: "einzahlung", betrag: betrag, text: text))
            }
        }

        store.speichereMitglieder(aktuelleMitglieder)
        store.speichereKasse(kasse)
        mitglieder = aktuelleMitglieder.players
    }

    // Called after sort – start actual game
    func spielStarten(orderedNames: [String], gäste: [Player]) {
        var aktuelleMitglieder = store.ladeMitglieder()

        // Add guests to mitglieder temporarily
        for gast in gäste {
            aktuelleMitglieder.players[gast.name] = gast.toPlayerData()
        }
        store.speichereMitglieder(aktuelleMitglieder)
        mitglieder = aktuelleMitglieder.players

        players = orderedNames.compactMap { name in
            aktuelleMitglieder.players[name].map { Player(name: name, data: $0) }
        }

        speichereAktuellesSpiel()
        gameRunning = true
        abgerechnet = false
        activeSheet = .game
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

    func berechneBillingRows() -> [BillingRow] {
        let ranking = resolveRanking()
        let n = Double(players.count)
        guard n > 0 else { return [] }

        // Total pumpen cost shared equally
        let gesamtPumpen = players.map { $0.pumpen + (tiebreakExtras[$0.name]?.pumpen ?? 0) }.reduce(0, +)
        let pumpenProKopf = Double(gesamtPumpen) * kasse.Pumpe / n

        var rows: [BillingRow] = []
        for (platz, player) in ranking.enumerated() {
            let myNeuner = player.neuner + (tiebreakExtras[player.name]?.neuner ?? 0)
            let myKranz = player.kranz + (tiebreakExtras[player.name]?.kranz ?? 0)

            // All OTHER players pay for this player's neuner/kranz
            // → this player pays sum of all OTHER players' neuner+kranz
            var zuZahlen = pumpenProKopf
            for other in players where other.name != player.name {
                let otherNeuner = other.neuner + (tiebreakExtras[other.name]?.neuner ?? 0)
                let otherKranz = other.kranz + (tiebreakExtras[other.name]?.kranz ?? 0)
                zuZahlen += Double(otherNeuner) * kasse.Neuner
                zuZahlen += Double(otherKranz) * kasse.Kranz
            }
            _ = myNeuner; _ = myKranz  // used in calc above indirectly

            rows.append(BillingRow(platz: platz + 1, player: player, zuZahlen: round2(zuZahlen)))
        }
        return rows
    }

    func resolveRanking() -> [Player] {
        // Group by summe descending
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
                // Check pumpen tiebreak
                let pumpenCounts = gruppe.map { $0.pumpen + (tiebreakExtras[$0.name]?.pumpen ?? 0) }
                let maxPumpen = pumpenCounts.max() ?? 0
                let mitMaxPumpen = gruppe.filter {
                    ($0.pumpen + (tiebreakExtras[$0.name]?.pumpen ?? 0)) == maxPumpen
                }
                if mitMaxPumpen.count == 1 {
                    // Most pumpen → worst rank
                    let rest = gruppe.filter { $0.name != mitMaxPumpen[0].name }
                    result.append(contentsOf: rest)
                    result.append(mitMaxPumpen[0])
                } else {
                    // True tie – add as-is (tiebreak must be done separately)
                    result.append(contentsOf: gruppe)
                }
            }
            i = j
        }
        return result
    }

    func abrechnungSpeichern(rows: [BillingRow]) {
        let datum = formatDatum(Date())

        for row in rows {
            let betrag = round2(row.zuZahlen)
            if betrag > 0 {
                let text = "\(datum) - Strafenanteil von \(row.player.name): \(String(format: "%.2f", betrag))€"
                kasse.Kassenstand += betrag
                kasse.Transaktionen.append(text)
                sessionTx.append((kind: "einzahlung", betrag: betrag, text: text))
            }
            let spende = round2(row.spende)
            if spende > 0 {
                let text = "\(datum) - Spende von \(row.player.name): \(String(format: "%.2f", spende))€"
                kasse.Kassenstand += spende
                kasse.Transaktionen.append(text)
                sessionTx.append((kind: "einzahlung", betrag: spende, text: text))
            }
        }

        // Bahngebühr abziehen
        if kasse.Bahngebuehr > 0 {
            let text = "\(datum) - Bahngebühr: -\(String(format: "%.2f", kasse.Bahngebuehr))€"
            kasse.Kassenstand = max(0, kasse.Kassenstand - kasse.Bahngebuehr)
            kasse.Transaktionen.append(text)
            sessionTx.append((kind: "auszahlung", betrag: kasse.Bahngebuehr, text: text))
        }

        store.speichereKasse(kasse)

        // Archiviere Spiel
        var historic = store.ladeHistorie()
        let entry = HistorieEntry(
            datum: datum,
            players: Dictionary(uniqueKeysWithValues: players.map { ($0.name, $0.toPlayerData()) }),
            transaktionen: kasse.Transaktionen,
            spieler_reihenfolge: players.map { $0.name }
        )
        historic.append(entry)
        store.speichereHistorie(historic)

        // Reset game state
        abgerechnet = true
        gameRunning = false
        tiebreakExtras = [:]
        sessionTx = []
        preSessionSchulden = [:]

        let emptySpiel = AktuellesSpielFile(
            players: [:], runde: 0, abgerechnet: true, spieler_reihenfolge: nil
        )
        store.speichereAktuellesSpiel(emptySpiel)
    }

    // MARK: - Game abort (Rollback)

    func spielAbbrechen() {
        // Rollback transactions in reverse
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

        // Restore pre-session debts
        var aktuelleMitglieder = store.ladeMitglieder()
        for (name, schuld) in preSessionSchulden {
            aktuelleMitglieder.players[name]?.offene_zahlung = schuld
        }
        store.speichereMitglieder(aktuelleMitglieder)
        mitglieder = aktuelleMitglieder.players

        // Reset
        sessionTx = []
        preSessionSchulden = [:]
        tiebreakExtras = [:]
        players = []
        gameRunning = false

        let empty = AktuellesSpielFile(players: [:], runde: 0, abgerechnet: false, spieler_reihenfolge: nil)
        store.speichereAktuellesSpiel(empty)
    }

    // MARK: - Cash management

    func einzahlen(betrag: Double, beschreibung: String, spielerName: String? = nil) {
        guard betrag > 0 else { return }
        let datum = formatDatum(Date())
        let text = "\(datum) | +\(String(format: "%.2f", betrag))€: \(beschreibung)"
        kasse.Kassenstand += betrag
        kasse.Transaktionen.append(text)

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

    func auszahlen(betrag: Double, beschreibung: String) {
        guard betrag > 0, betrag <= kasse.Kassenstand else { return }
        let datum = formatDatum(Date())
        let text = "\(datum) | -\(String(format: "%.2f", betrag))€: \(beschreibung)"
        kasse.Kassenstand -= betrag
        kasse.Transaktionen.append(text)
        store.speichereKasse(kasse)
    }

    // MARK: - Player management

    func spielerHinzufügen(name: String, typ: String, offeneZahlung: Double) {
        var m = store.ladeMitglieder()
        var pd = PlayerData(typ: typ)
        pd.offene_zahlung = offeneZahlung
        m.players[name] = pd
        store.speichereMitglieder(m)
        mitglieder = m.players
    }

    func spielerBearbeiten(alterName: String, neuerName: String, typ: String, offeneZahlung: Double) {
        var m = store.ladeMitglieder()
        var pd = m.players[alterName] ?? PlayerData(typ: typ)
        pd.typ = typ
        pd.offene_zahlung = offeneZahlung
        if alterName != neuerName {
            m.players.removeValue(forKey: alterName)
        }
        m.players[neuerName] = pd
        store.speichereMitglieder(m)
        mitglieder = m.players
    }

    func spielerLöschen(name: String) {
        var m = store.ladeMitglieder()
        m.players.removeValue(forKey: name)
        store.speichereMitglieder(m)
        mitglieder = m.players
    }

    // MARK: - Settings

    func einstellungenSpeichern(_ neueKasse: KasseFile) {
        kasse = neueKasse
        store.speichereKasse(kasse)
    }

    // MARK: - Helpers

    private func speichereAktuellesSpiel() {
        let dict = Dictionary(uniqueKeysWithValues: players.map { ($0.name, $0.toPlayerData()) })
        let spiel = AktuellesSpielFile(
            players: dict,
            runde: runde,
            abgerechnet: abgerechnet,
            spieler_reihenfolge: players.map { $0.name }
        )
        store.speichereAktuellesSpiel(spiel)
    }

    func formatDatum(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "dd.MM.yyyy"
        return df.string(from: date)
    }

    private func round2(_ val: Double) -> Double {
        (val * 100).rounded() / 100
    }

    var letzterSpieltag: [String] {
        let historic = store.ladeHistorie()
        if let last = historic.last {
            return last.spieler_reihenfolge ?? Array(last.players.keys).sorted()
        }
        return []
    }
}
