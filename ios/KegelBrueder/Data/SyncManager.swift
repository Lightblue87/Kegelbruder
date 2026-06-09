import Foundation
import SwiftUI

// MARK: - SyncManager: monitors iCloud Drive sync status for kegelbruder.db
// iCloud handles upload/download automatically – we only need to reload
// the local SQLite connection when the file changes from another device.

@MainActor
class SyncManager: ObservableObject {

    static let shared = SyncManager()

    @Published var status: SyncStatus = .idle
    @Published var lastSync: Date? = nil

    private var metadataQuery: NSMetadataQuery?
    private var isMonitoring = false

    private init() {}

    // Backward-compat property (KegelBruederApp checks sync.hasLink)
    var hasLink: Bool { DataStore.shared.iCloudAvailable }

    // MARK: - Start iCloud file monitoring

    func startMonitoring() {
        guard DataStore.shared.iCloudAvailable, !isMonitoring else { return }
        isMonitoring = true

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(
            format: "%K == %@", NSMetadataItemFSNameKey, "kegelbruder.db"
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )

        query.start()
        self.metadataQuery = query
    }

    func stopMonitoring() {
        metadataQuery?.stop()
        metadataQuery = nil
        isMonitoring = false
    }

    @objc private func queryDidUpdate(notification: Notification) {
        // Called when iCloud pushes an updated DB from another device
        Task { @MainActor in
            self.status = .syncing("iCloud synchronisiert…")
            DataStore.shared.reloadDatabase()
            self.lastSync = Date()
            self.status = .success("Synchronisiert \(self.formatTime(Date()))")
        }
    }

    // MARK: - Manual refresh (user-triggered)

    func downloadAll() async {
        guard DataStore.shared.iCloudAvailable else {
            status = .error("iCloud nicht verfügbar")
            return
        }
        status = .syncing("Daten werden geladen…")
        DataStore.shared.reloadDatabase()
        lastSync = Date()
        status = .success("Synchronisiert \(formatTime(Date()))")
    }

    // Legacy – no-op since iCloud uploads automatically
    func uploadAll(from store: DataStore) async {}
    func uploadFile(_ filename: String, data: Data) async {}

    // MARK: - Link validation (no longer needed – kept for backward compat)

    func validateAndSaveLink(_ link: String) async -> Bool { false }
    func setLink(_ link: String) {}
    var sharingLink: String { "" }

    // MARK: - Helper

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
