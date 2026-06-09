import Foundation
import UIKit

// MARK: - DataStore: handles all file I/O with the chosen OneDrive/Files folder

@MainActor
class DataStore: ObservableObject {

    static let shared = DataStore()

    // Persisted security-scoped bookmark to the chosen data folder
    private let bookmarkKey = "dataFolderBookmark"

    @Published var folderURL: URL? = nil
    @Published var folderName: String = ""

    private init() {
        restoreBookmark()
    }

    // MARK: - Folder selection

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
            if isStale {
                saveBookmark(for: url)
            } else {
                folderURL = url
                folderName = url.lastPathComponent
            }
        } catch {
            print("Bookmark wiederherstellen fehlgeschlagen: \(error)")
        }
    }

    // MARK: - Generic read/write

    func fileURL(_ filename: String) -> URL? {
        guard let folder = folderURL else { return nil }
        return folder.appendingPathComponent(filename)
    }

    func read<T: Decodable>(_ filename: String, default defaultValue: T) -> T {
        guard let url = fileURL(filename) else { return defaultValue }
        guard url.startAccessingSecurityScopedResource() else { return defaultValue }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("Lesen von \(filename) fehlgeschlagen: \(error)")
            return defaultValue
        }
    }

    func write<T: Encodable>(_ filename: String, value: T) {
        guard let folder = folderURL,
              let url = fileURL(filename) else { return }
        guard folder.startAccessingSecurityScopedResource() else { return }
        defer { folder.stopAccessingSecurityScopedResource() }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(value)

            // Atomic write: write to temp file first, then replace
            let tempURL = folder.appendingPathComponent("\(filename).tmp")
            try data.write(to: tempURL, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tempURL)

            // Auto-upload to OneDrive if link configured
            if filename != "kegelbruder.lock" {
                Task {
                    await SyncManager.shared.uploadFile(filename, data: data)
                }
            }
        } catch {
            print("Schreiben von \(filename) fehlgeschlagen: \(error)")
        }
    }

    func fileExists(_ filename: String) -> Bool {
        guard let url = fileURL(filename) else { return false }
        guard (folderURL ?? url).startAccessingSecurityScopedResource() else { return false }
        defer { (folderURL ?? url).stopAccessingSecurityScopedResource() }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func deleteFile(_ filename: String) {
        guard let url = fileURL(filename),
              let folder = folderURL else { return }
        guard folder.startAccessingSecurityScopedResource() else { return }
        defer { folder.stopAccessingSecurityScopedResource() }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Typed convenience accessors

    func ladeMitglieder() -> MitgliederFile {
        read("mitglieder.json", default: MitgliederFile(players: [:]))
    }

    func speichereMitglieder(_ file: MitgliederFile) {
        write("mitglieder.json", value: file)
    }

    func ladeKasse() -> KasseFile {
        read("kasse.json", default: KasseFile.defaultValue)
    }

    func speichereKasse(_ file: KasseFile) {
        write("kasse.json", value: file)
    }

    func ladeAktuellesSpiel() -> AktuellesSpielFile {
        read("aktuelles_spiel.json", default: AktuellesSpielFile(
            players: [:], runde: 0, abgerechnet: false, spieler_reihenfolge: nil
        ))
    }

    func speichereAktuellesSpiel(_ file: AktuellesSpielFile) {
        write("aktuelles_spiel.json", value: file)
    }

    func ladeHistorie() -> [HistorieEntry] {
        read("historie.json", default: [HistorieEntry]())
    }

    func speichereHistorie(_ entries: [HistorieEntry]) {
        let limited = Array(entries.suffix(100))
        write("historie.json", value: limited)
    }

    // MARK: - Lock file

    let lockFilename = "kegelbruder.lock"

    func ladeLock() -> AppLockFile? {
        guard fileExists(lockFilename) else { return nil }
        return read(lockFilename, default: Optional<AppLockFile>.none)
    }

    func setzeLock() {
        let lock = AppLockFile(
            gerät: UIDevice.current.name,
            seit: ISO8601DateFormatter().string(from: Date()),
            plattform: "iOS"
        )
        write(lockFilename, value: lock)
    }

    func loescheLock() {
        deleteFile(lockFilename)
    }

    func lockIstAbgelaufen(_ lock: AppLockFile) -> Bool {
        let formatter = ISO8601DateFormatter()
        guard let seit = formatter.date(from: lock.seit) else { return true }

        let calendar = Calendar.current
        let jetzt = Date()

        // Letzter 01:00-Uhr-Reset-Zeitpunkt
        var components = calendar.dateComponents([.year, .month, .day], from: jetzt)
        components.hour = 1
        components.minute = 0
        components.second = 0

        guard let resetHeute = calendar.date(from: components) else { return true }
        let letzterReset = jetzt >= resetHeute
            ? resetHeute
            : calendar.date(byAdding: .day, value: -1, to: resetHeute)!

        return seit < letzterReset
    }
}

// Optional Codable conformance for reading optional types
extension Optional: Decodable where Wrapped: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .none
        } else {
            self = try .some(Wrapped(from: decoder))
        }
    }
}
