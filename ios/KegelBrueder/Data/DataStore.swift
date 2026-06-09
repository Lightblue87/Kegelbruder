import Foundation
import UIKit

// MARK: - DataStore: manages the local SQLite DB cache + folder bookmark

@MainActor
class DataStore: ObservableObject {

    static let shared = DataStore()

    private let bookmarkKey = "dataFolderBookmark"
    private let dbFilename  = "kegelbruder.db"

    @Published var folderURL: URL? = nil
    @Published var folderName: String = ""

    private(set) var sqlite: SQLiteStore? = nil

    private init() {
        restoreBookmark()
    }

    // MARK: - Folder selection & bookmark

    func saveBookmark(for url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let bookmark = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            folderURL = url
            folderName = url.lastPathComponent
            openDatabase(in: url)
        } catch {
            print("Bookmark speichern fehlgeschlagen: \(error)")
        }
    }

    func restoreBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale { saveBookmark(for: url) } else {
                folderURL = url
                folderName = url.lastPathComponent
                openDatabase(in: url)
            }
        } catch {
            print("Bookmark wiederherstellen fehlgeschlagen: \(error)")
        }
    }

    private func openDatabase(in folder: URL) {
        guard folder.startAccessingSecurityScopedResource() else { return }
        defer { folder.stopAccessingSecurityScopedResource() }
        let dbURL = folder.appendingPathComponent(dbFilename)
        do {
            sqlite = try SQLiteStore(path: dbURL.path)
        } catch {
            print("SQLite öffnen fehlgeschlagen: \(error)")
        }
    }

    // MARK: - DB file URL (for OneDrive upload/download)

    func dbFileURL() -> URL? {
        folderURL?.appendingPathComponent(dbFilename)
    }

    func dbFileData() -> Data? {
        guard let url = dbFileURL(),
              let folder = folderURL,
              folder.startAccessingSecurityScopedResource() else { return nil }
        defer { folder.stopAccessingSecurityScopedResource() }
        return try? Data(contentsOf: url)
    }

    func replaceDatabase(with data: Data) {
        guard let url = dbFileURL(),
              let folder = folderURL,
              folder.startAccessingSecurityScopedResource() else { return }
        defer { folder.stopAccessingSecurityScopedResource() }

        // Close current connection, replace file, reopen
        sqlite = nil
        do {
            try data.write(to: url, options: .atomic)
            sqlite = try SQLiteStore(path: url.path)
        } catch {
            print("Datenbank ersetzen fehlgeschlagen: \(error)")
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
        // Historie ist append-only – einzelne Einträge werden via archivierSpiel() geschrieben
    }

    func archivierSpiel(datum: String, players: [String: PlayerData],
                        transaktionen: [String], reihenfolge: [String]) {
        try? sqlite?.archivierSpiel(datum: datum, players: players,
                                    transaktionen: transaktionen, reihenfolge: reihenfolge)
    }

    // MARK: - Lock (via SQLite app_lock table)

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
        let calendar = Calendar.current
        let jetzt = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: jetzt)
        components.hour = 1; components.minute = 0; components.second = 0
        guard let resetHeute = calendar.date(from: components) else { return true }
        let letzterReset = jetzt >= resetHeute
            ? resetHeute
            : calendar.date(byAdding: .day, value: -1, to: resetHeute)!
        return seit < letzterReset
    }

    // MARK: - Misc

    func write<T: Encodable>(_ filename: String, value: T) {
        // Kept for SyncManager compatibility; actual data goes through typed methods above
    }
}
