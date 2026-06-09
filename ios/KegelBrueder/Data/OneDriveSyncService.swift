import Foundation

// MARK: - OneDrive Graph API Sync via Sharing Link
// Requires "Anyone with the link can edit" sharing link from OneDrive.
// Uses the Microsoft Graph API sharing token approach (no OAuth needed for anonymous edit links).

actor OneDriveSyncService {

    static let shared = OneDriveSyncService()

    private let graphBase = "https://graph.microsoft.com/v1.0"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }

    // MARK: - Sharing link encoding (Microsoft Graph spec)

    func encodeSharingUrl(_ url: String) -> String {
        let data = Data(url.utf8)
        let base64 = data.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return "u!\(base64)"
    }

    private func shareRoot(_ sharingLink: String) -> String {
        let id = encodeSharingUrl(sharingLink)
        return "\(graphBase)/shares/\(id)/root"
    }

    // MARK: - List files in shared folder

    func listFiles(sharingLink: String) async throws -> [String] {
        let url = URL(string: "\(shareRoot(sharingLink)):/children")!
        let (data, response) = try await session.data(from: url)
        try checkResponse(response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let items = json?["value"] as? [[String: Any]] ?? []
        return items.compactMap { $0["name"] as? String }
    }

    // MARK: - Download a file

    func downloadFile(sharingLink: String, filename: String) async throws -> Data {
        // First get the download URL via metadata
        let metaURL = URL(string: "\(shareRoot(sharingLink)):/\(filename):")!
        var metaReq = URLRequest(url: metaURL)
        metaReq.addValue("application/json", forHTTPHeaderField: "Accept")
        let (metaData, metaResponse) = try await session.data(for: metaReq)
        try checkResponse(metaResponse, data: metaData)

        guard
            let json = try JSONSerialization.jsonObject(with: metaData) as? [String: Any],
            let downloadUrl = json["@microsoft.graph.downloadUrl"] as? String,
            let dlURL = URL(string: downloadUrl)
        else {
            throw SyncError.noDownloadUrl(filename)
        }

        let (fileData, fileResponse) = try await session.data(from: dlURL)
        try checkResponse(fileResponse, data: fileData)
        return fileData
    }

    // MARK: - Upload a file

    func uploadFile(sharingLink: String, filename: String, data: Data) async throws {
        let uploadURL = URL(string: "\(shareRoot(sharingLink)):/\(filename):/content")!
        var req = URLRequest(url: uploadURL)
        req.httpMethod = "PUT"
        req.addValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = data

        let (responseData, response) = try await session.data(for: req)
        try checkResponse(response, data: responseData)
    }

    // MARK: - Sync: download all known JSON files

    func downloadAll(sharingLink: String) async throws -> [String: Data] {
        let filenames = [
            "mitglieder.json",
            "kasse.json",
            "aktuelles_spiel.json",
            "historie.json",
            "kegelbruder.lock"
        ]

        var result: [String: Data] = [:]
        for filename in filenames {
            do {
                let data = try await downloadFile(sharingLink: sharingLink, filename: filename)
                result[filename] = data
            } catch SyncError.httpError(404, _) {
                // File doesn't exist yet – skip
                continue
            }
        }
        return result
    }

    // MARK: - Response validation

    private func checkResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SyncError.httpError(http.statusCode, body)
        }
    }

    // MARK: - Validate sharing link

    func validateLink(_ sharingLink: String) async -> Bool {
        guard sharingLink.lowercased().hasPrefix("https://") else { return false }
        do {
            _ = try await listFiles(sharingLink: sharingLink)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Errors

enum SyncError: LocalizedError {
    case invalidResponse
    case httpError(Int, String)
    case noDownloadUrl(String)
    case noLink

    var errorDescription: String? {
        switch self {
        case .invalidResponse:         return "Ungültige Server-Antwort"
        case .httpError(404, _):       return "Datei nicht gefunden"
        case .httpError(401, _), .httpError(403, _):
            return "Zugriff verweigert – prüfe ob der Link Schreibrechte hat"
        case .httpError(let code, let body):
            return "Serverfehler \(code): \(body.prefix(200))"
        case .noDownloadUrl(let f):    return "Kein Download-Link für \(f)"
        case .noLink:                  return "Kein OneDrive-Link konfiguriert"
        }
    }
}
