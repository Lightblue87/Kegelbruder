import Foundation
import UIKit

// MARK: - DataStore: manages the SQLite DB via iCloud Drive ubiquity container
// Falls back to local Documents if iCloud is not available.

@MainActor
class DataStore: ObservableObject {

    static let shared = DataStore()

    private let dbFilename       = "kegelbruder.db"
    private let containerID      = "iCloud.de.kegelbruder.app"

    @Published var isReady:         Bool = false
    @Published var iCloudAvailable: Bool = false
    @Published var dbPath:          String = ""

    private(set) var sqlite: SQLiteStore? = nil

    // Computed for backward compatibility with code that checks folderURL != nil
    var folderURL: URL? {
        sqlite.map { URL(fileURLWithPath: $0.path).deletingLastPathComponent() }
    }

    private init() {}

    // MARK: - Startup: resolve iCloud container URL (must run async, blocks main thread otherwise)

    func setUp() async {
        let (dbURL, cloudAvailable) = await Task.detached(priority: .userInitiated) { [self] in
            if let container = FileManager.default.url(
                forUbiquityContainerIdentifier: self.containerID
            ) {
                let docs = container.appendingPathComponent("Documents")
                try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
                return (docs.appendingPathComponent(self.dbFilename), true)
            } else {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                return (docs.appendingPathComponent(self.dbFilename), false)
            }
        }.value

        openDatabase(at: dbURL)
        iCloudAvailable = cloudAvailable
        dbPath          = dbURL.path
        isReady         = true
    }

    func reloadDatabase() {
        guard let path = sqlite?.path else { return }
        sqlite = nil
        openDatabase(at: URL(fileURLWithPath: path))
    }

    private func openDatabase(at url: URL) {
        do {
            sqlite = try SQLiteStore(path: url.path)
        } catch {
            print("SQLite öffnen fehlgeschlagen: \(error)")
        }
    }

    // MARK: - Typed accessors (delegate to SQLiteStore)

    func ladeMitglieder() -> MitgliederFile {
        MitgliederFile(players: sqlite?.ladeMitglieder() ?? [:])
    }

    func speichereMitglieder(_ file: MitgliederFile) {
        try? sqlite?.speichereMitglieder(file.players)
    }

    func ladeKasse() -> KasseFile {
        guard let db = sqlite else { return KasseFile.defaultValue }
        let e = db.ladeKasseEinstellungen()
        return KasseFile(
            Startgeld:              e["Startgeld"]              ?? 5.0,
            Pumpe:                  e["Pumpe"]                  ?? 0.5,
            Neuner:                 e["Neuner"]                 ?? 1.0,
            Kranz:                  e["Kranz"]                  ?? 2.0,
            Strafe_Stamm:           e["Strafe Stamm"]           ?? 7.5,
            Bahngebuehr:            e["Bahngebühr"]             ?? 30.0,
            Kassenstand:            e["Kassenstand"]            ?? 0.0,
            Transaktionen:          db.ladeTransaktionen(),
            Letzte_Startgebuehren:  e["Letzte_Startgebuehren"]  ?? 0.0
        )
    }

    func speichereKasse(_ file: KasseFile) {
        let einstellungen: [String: Double] = [
            "Startgeld":             file.Startgeld,
            "Pumpe":                 file.Pumpe,
            "Neuner":                file.Neuner,
            "Kranz":                 file.Kranz,
            "Strafe Stamm":          file.Strafe_Stamm,
            "Bahngebühr":            file.Bahngebuehr,
            "Kassenstand":           file.Kassenstand,
            "Letzte_Startgebuehren": file.Letzte_Startgebuehren
        ]
        try? sqlite?.speichereKasse(einstellungen: einstellungen,
                                    transaktionen: file.Transaktionen)
    }

    func ladeAktuellesSpiel() -> AktuellesSpielFile {
        sqlite?.ladeAktuellesSpiel() ?? AktuellesSpielFile(
            players: [:], runde: 0, abgerechnet: false, spieler_reihenfolge: nil
        )
    }

    func speichereAktuellesSpiel(_ file: AktuellesSpielFile) {
        try? sqlite?.speichereAktuellesSpiel(file)
    }

    func ladeHistorie() -> [HistorieEntry] {
        sqlite?.ladeHistorie() ?? []
    }

    func speichereHistorie(_ entries: [HistorieEntry]) {
        // append-only – einzelne Einträge via archivierSpiel()
    }

    func archivierSpiel(datum: String, players: [String: PlayerData],
                        transaktionen: [String], reihenfolge: [String]) {
        try? sqlite?.archivierSpiel(datum: datum, players: players,
                                    transaktionen: transaktionen, reihenfolge: reihenfolge)
    }

    // MARK: - Lock

    func ladeLock() -> AppLockFile? {
        sqlite?.ladeLock()
    }

    func setzeLock() {
        let formatter = ISO8601DateFormatter()
        try? sqlite?.setzeLock(
            geraet: UIDevice.current.name,
            seit: formatter.string(from: Date()),
            plattform: "iOS"
        )
    }

    func loescheLock() {
        try? sqlite?.loescheLock()
    }

    func lockIstAbgelaufen(_ lock: AppLockFile) -> Bool {
        let formatter = ISO8601DateFormatter()
        guard let seit = formatter.date(from: lock.seit) else { return true }
        let calendar  = Calendar.current
        let jetzt     = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: jetzt)
        components.hour = 1; components.minute = 0; components.second = 0
        guard let resetHeute = calendar.date(from: components) else { return true }
        let letzterReset = jetzt >= resetHeute
            ? resetHeute
            : calendar.date(byAdding: .day, value: -1, to: resetHeute)!
        return seit < letzterReset
    }

    // MARK: - Misc (kept for SyncManager compatibility)

    func write<T: Encodable>(_ filename: String, value: T) {}

    func dbFileData() -> Data? {
        guard let path = sqlite?.path else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }
}
