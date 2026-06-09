import Foundation
import Combine

// MARK: - SyncManager: orchestrates local DataStore ↔ OneDrive sync

@MainActor
class SyncManager: ObservableObject {

    static let shared = SyncManager()

    private let oneDrive = OneDriveSyncService.shared
    private let linkKey = "oneDriveSharingLink"

    @Published var status: SyncStatus = .idle
    @Published var lastSync: Date? = nil
    @Published var sharingLink: String = ""

    private init() {
        sharingLink = UserDefaults.standard.string(forKey: linkKey) ?? ""
    }

    // MARK: - Link management

    var hasLink: Bool { !sharingLink.trimmingCharacters(in: .whitespaces).isEmpty }

    func setLink(_ link: String) {
        sharingLink = link.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(sharingLink, forKey: linkKey)
    }

    func validateAndSaveLink(_ link: String) async -> Bool {
        status = .syncing("Link wird geprüft…")
        let ok = await oneDrive.validateLink(link)
        if ok {
            setLink(link)
            status = .success("Link gespeichert ✓")
        } else {
            status = .error("Link ungültig oder kein Schreibzugriff")
        }
        return ok
    }

    // MARK: - Download (OneDrive → lokal)

    func downloadAll() async {
        guard hasLink else { status = .idle; return }
        status = .syncing("Daten werden geladen…")

        do {
            let files = try await oneDrive.downloadAll(sharingLink: sharingLink)
            applyDownloaded(files)
            lastSync = Date()
            status = .success("Synchronisiert \(formatTime(lastSync!))")
        } catch {
            status = .error("Download fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    // MARK: - Upload (lokal → OneDrive)

    func uploadFile(_ filename: String, data: Data) async {
        guard hasLink else { return }
        do {
            try await oneDrive.uploadFile(sharingLink: sharingLink, filename: filename, data: data)
            lastSync = Date()
        } catch {
            status = .error("Upload \(filename): \(error.localizedDescription)")
        }
    }

    func uploadAll(from store: DataStore) async {
        guard hasLink else { return }
        status = .syncing("Daten werden hochgeladen…")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let filesToUpload: [(String, Encodable)] = [
            ("mitglieder.json",    store.ladeMitglieder()),
            ("kasse.json",         store.ladeKasse()),
            ("aktuelles_spiel.json", store.ladeAktuellesSpiel()),
            ("historie.json",      store.ladeHistorie()),
        ]

        for (filename, value) in filesToUpload {
            guard let data = try? encoder.encode(AnyEncodable(value)) else { continue }
            await uploadFile(filename, data: data)
        }

        lastSync = Date()
        status = .success("Hochgeladen \(formatTime(lastSync!))")
    }

    // MARK: - Apply downloaded data to local DataStore

    private func applyDownloaded(_ files: [String: Data]) {
        let store = DataStore.shared
        let decoder = JSONDecoder()

        if let data = files["mitglieder.json"],
           let decoded = try? decoder.decode(MitgliederFile.self, from: data) {
            store.speichereMitglieder(decoded)
        }

        if let data = files["kasse.json"],
           let decoded = try? decoder.decode(KasseFile.self, from: data) {
            store.speichereKasse(decoded)
        }

        if let data = files["aktuelles_spiel.json"],
           let decoded = try? decoder.decode(AktuellesSpielFile.self, from: data) {
            store.speichereAktuellesSpiel(decoded)
        }

        if let data = files["historie.json"],
           let decoded = try? decoder.decode([HistorieEntry].self, from: data) {
            store.speichereHistorie(decoded)
        }

        if let data = files["kegelbruder.lock"],
           let decoded = try? decoder.decode(AppLockFile.self, from: data) {
            // Only write lock if it exists remotely
            store.write("kegelbruder.lock", value: decoded)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Sync status

enum SyncStatus: Equatable {
    case idle
    case syncing(String)
    case success(String)
    case error(String)

    var message: String {
        switch self {
        case .idle:             return ""
        case .syncing(let m):  return m
        case .success(let m):  return m
        case .error(let m):    return m
        }
    }

    var color: some View {
        switch self {
        case .idle:    return Color.secondary
        case .syncing: return Color.blue
        case .success: return Color.green
        case .error:   return Color.red
        }
    }

    var isLoading: Bool {
        if case .syncing = self { return true }
        return false
    }
}

// MARK: - Type-erased Encodable helper

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ value: Encodable) { self._encode = value.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}

// SwiftUI import for color
import SwiftUI
