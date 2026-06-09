import Foundation
import SwiftUI

// MARK: - SyncManager: manual reload trigger + status display
// Automatic sync happens via iCloud Drive in the background;
// we reload the SQLite connection when the app returns to foreground
// (see KegelBruederApp onChange(of: scenePhase)).

@MainActor
class SyncManager: ObservableObject {

    static let shared = SyncManager()

    @Published var status: SyncStatus = .idle
    @Published var lastSync: Date? = nil

    private init() {}

    var hasLink: Bool { DataStore.shared.iCloudAvailable }

    func startMonitoring() {}
    func stopMonitoring() {}

    // Manual reload triggered by the user tapping the refresh button in Settings
    func downloadAll() async {
        guard DataStore.shared.iCloudAvailable else {
            status = .error("Kein Ordner gewählt")
            return
        }
        status = .syncing("Daten werden geladen…")
        DataStore.shared.reloadDatabase()
        lastSync = Date()
        status = .success("Aktualisiert \(formatTime(Date()))")
    }

    // Legacy stubs
    func uploadAll(from store: DataStore) async {}
    func uploadFile(_ filename: String, data: Data) async {}
    func validateAndSaveLink(_ link: String) async -> Bool { false }
    func setLink(_ link: String) {}
    var sharingLink: String { "" }

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
