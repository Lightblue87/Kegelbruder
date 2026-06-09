import Foundation
import SwiftUI

// MARK: - SyncManager: up/download kegelbruder.db via OneDrive Graph API

@MainActor
class SyncManager: ObservableObject {

    static let shared = SyncManager()

    private let oneDrive = OneDriveSyncService.shared
    private let linkKey  = "oneDriveSharingLink"
    private let dbFilename = "kegelbruder.db"

    @Published var status: SyncStatus = .idle
    @Published var lastSync: Date? = nil
    @Published var sharingLink: String = ""

    private init() {
        sharingLink = UserDefaults.standard.string(forKey: linkKey) ?? ""
    }

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

    // MARK: - Download DB from OneDrive → replace local DB

    func downloadAll() async {
        guard hasLink else { status = .idle; return }
        status = .syncing("Datenbank wird geladen…")
        do {
            let data = try await oneDrive.downloadFile(
                sharingLink: sharingLink, filename: dbFilename
            )
            await DataStore.shared.replaceDatabase(with: data)
            lastSync = Date()
            status = .success("Synchronisiert \(formatTime(lastSync!))")
        } catch SyncError.httpError(404, _) {
            // DB existiert noch nicht in OneDrive – erster Start, kein Fehler
            status = .idle
        } catch {
            status = .error("Download fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    // MARK: - Upload local DB → OneDrive

    func uploadAll(from store: DataStore) async {
        guard hasLink else { return }
        guard let data = store.dbFileData() else { return }
        status = .syncing("Datenbank wird hochgeladen…")
        do {
            try await oneDrive.uploadFile(
                sharingLink: sharingLink, filename: dbFilename, data: data
            )
            lastSync = Date()
            status = .success("Hochgeladen \(formatTime(lastSync!))")
        } catch {
            status = .error("Upload fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    // Einzeldatei-Upload (wird von DataStore.write() aufgerufen – jetzt ein No-op,
    // da wir die ganze DB uploaden, nicht einzelne Dateien)
    func uploadFile(_ filename: String, data: Data) async {
        // Bei SQLite-basiertem Sync wird die ganze DB hochgeladen, nicht einzelne Dateien.
        // Trigger: nach jeder Schreiboperation die DB hochladen.
        await uploadAll(from: DataStore.shared)
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
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
        case .idle:            return ""
        case .syncing(let m): return m
        case .success(let m): return m
        case .error(let m):   return m
        }
    }

    var isLoading: Bool { if case .syncing = self { return true }; return false }
}
