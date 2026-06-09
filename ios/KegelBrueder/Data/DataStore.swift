import Foundation
import UIKit

// MARK: - DataStore: SQLite DB via user-chosen folder (security-scoped bookmark)
// The user picks any accessible folder — local, iCloud Drive (own or shared with
// full-access link). The folder URL is persisted as a security-scoped bookmark in
// UserDefaults so the app can reopen the same location without a picker on every launch.

@MainActor
class DataStore: ObservableObject {

    static let shared = DataStore()

    private let dbFilename  = "kegelbruder.db"
    private let bookmarkKey = "dataFolderBookmark"

    @Published var isReady:         Bool   = false
    @Published var iCloudAvailable: Bool   = false   // true = a valid folder bookmark is active
    @Published var writeAccessOK:   Bool   = false
    @Published var dbPath:          String = ""
    @Published var folderName:      String = ""

    private(set) var sqlite: SQLiteStore? = nil
    private var scopedURL: URL? = nil

    private init() {}

    // MARK: - Startup

    func setUp() async {
        if restoreBookmark() {
            isReady = true
            return
        }
        // No folder chosen yet — fall back to local Documents so the app can start
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbURL = docs.appendingPathComponent(dbFilename)
        openDatabase(at: dbURL)
        iCloudAvailable = false
        dbPath    = dbURL.path
        folderName = "Lokal"
        isReady   = true
    }

    // MARK: - Folder selection (called after DocumentDirectoryPicker returns a URL)

    func saveBookmark(for url: URL) {
        // Release any previous security scope
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil

        // Start scope BEFORE creating bookmark — required on iOS
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if !scoped { } }   // scope kept alive via scopedURL below

        do {
            // Use [] (no options) — .minimalBookmark / .withSecurityScope are macOS-only
            let bookmark = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)

            if scoped { scopedURL = url }
            let dbURL = url.appendingPathComponent(dbFilename)
            openDatabase(at: dbURL)
            iCloudAvailable = true
            dbPath    = dbURL.path
            folderName = url.lastPathComponent
            writeAccessOK = verifyWriteAccess(in: url)
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            print("Bookmark speichern fehlgeschlagen: \(error)")
        }
    }

    // MARK: - Reload (foreground / manual sync)

    func reloadDatabase() {
        guard let path = sqlite?.path else { return }
        sqlite = nil
        openDatabase(at: URL(fileURLWithPath: path))
    }

    // MARK: - Private helpers

    @discardableResult
    private func restoreBookmark() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return false }
        var isStale = false
        do {
            // Use [] — .withSecurityScope is macOS-only
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                // Refresh the bookmark data with the new URL
                if let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: bookmarkKey)
                    return false
                }
            }
            let scoped = url.startAccessingSecurityScopedResource()
            if scoped { scopedURL = url }
            let dbURL = url.appendingPathComponent(dbFilename)
            openDatabase(at: dbURL)
            iCloudAvailable = true
            dbPath    = dbURL.path
            folderName = url.lastPathComponent
            writeAccessOK = verifyWriteAccess(in: url)
            return true
        } catch {
            print("Bookmark wiederherstellen fehlgeschlagen: \(error)")
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return false
        }
    }

    private func verifyWriteAccess(in folder: URL) -> Bool {
        let testURL = folder.appendingPathComponent(".kegelbruder_write_test")
        do {
            try "1".write(to: testURL, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: testURL)
            return true
        } catch { return false }
    }

    private func openDatabase(at url: URL) {
        do {
            sqlite = try SQLiteStore(path: url.path)
        } catch {
            print("SQLite öffnen fehlgeschlagen: \(error)")
        }
    }

    // MARK: - Typed accessors

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

    func ladeHistorie() -> [HistorieEntry] { sqlite?.ladeHistorie() ?? [] }

    func archivierSpiel(datum: String, players: [String: PlayerData],
                        transaktionen: [String], reihenfolge: [String]) {
        try? sqlite?.archivierSpiel(datum: datum, players: players,
                                    transaktionen: transaktionen, reihenfolge: reihenfolge)
    }

    // MARK: - Lock

    func ladeLock() -> AppLockFile? { sqlite?.ladeLock() }

    func setzeLock() {
        let formatter = ISO8601DateFormatter()
        try? sqlite?.setzeLock(geraet: UIDevice.current.name,
                               seit: formatter.string(from: Date()),
                               plattform: "iOS")
    }

    func loescheLock() { try? sqlite?.loescheLock() }

    func lockIstAbgelaufen(_ lock: AppLockFile) -> Bool {
        let formatter = ISO8601DateFormatter()
        guard let seit = formatter.date(from: lock.seit) else { return true }
        let calendar = Calendar.current
        let jetzt    = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: jetzt)
        components.hour = 1; components.minute = 0; components.second = 0
        guard let resetHeute = calendar.date(from: components) else { return true }
        let letzterReset = jetzt >= resetHeute
            ? resetHeute
            : calendar.date(byAdding: .day, value: -1, to: resetHeute)!
        return seit < letzterReset
    }

    // MARK: - Misc

    func write<T: Encodable>(_ filename: String, value: T) {}

    func dbFileData() -> Data? {
        guard let path = sqlite?.path else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }
}
