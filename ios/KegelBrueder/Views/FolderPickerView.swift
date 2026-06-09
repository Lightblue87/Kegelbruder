import SwiftUI
import UniformTypeIdentifiers

// MARK: - Erster Start: OneDrive Link oder lokalen Ordner wählen

struct FolderPickerView: View {
    @EnvironmentObject var store: DataStore
    @StateObject private var sync = SyncManager.shared

    @State private var linkInput: String = ""
    @State private var isValidating = false
    @State private var validationError: String? = nil
    @State private var showLocalPicker = false
    @State private var mode: SetupMode = .none

    enum SetupMode { case none, oneDrive, local }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "figure.bowling")
                        .font(.system(size: 64))
                        .foregroundColor(.accentColor)
                        .padding(.top, 40)
                    Text("Kegel Brüder")
                        .font(.largeTitle.bold())
                    Text("Wähle wie die Daten gespeichert werden sollen.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 32)

                // Mode selector
                Form {
                    // Option 1: OneDrive Freigabelink
                    Section {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { mode == .oneDrive },
                                set: { mode = $0 ? .oneDrive : .none }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Freigabelink eingeben:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                TextField("https://1drv.ms/f/s!A...", text: $linkInput)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                                    .padding(10)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .cornerRadius(8)

                                if let err = validationError {
                                    Label(err, systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }

                                Button {
                                    Task { await validateAndContinue() }
                                } label: {
                                    HStack {
                                        if isValidating {
                                            ProgressView().tint(.white)
                                        } else {
                                            Image(systemName: "checkmark.circle")
                                        }
                                        Text(isValidating ? "Wird geprüft…" : "Link bestätigen")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(linkInput.trimmingCharacters(in: .whitespaces).isEmpty || isValidating)

                                // Anleitung
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("So erstellst du den Link:")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                    ForEach([
                                        "1. OneDrive öffnen (Web oder Desktop)",
                                        "2. Ordner 'Kegelbruder' erstellen",
                                        "3. Rechtsklick → Teilen",
                                        "4. 'Jeder mit dem Link kann bearbeiten'",
                                        "5. Link kopieren und hier einfügen"
                                    ], id: \.self) { step in
                                        Text(step)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.top, 4)
                            }
                            .padding(.vertical, 4)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("OneDrive Freigabelink")
                                        .font(.headline)
                                    Text("Sync zwischen PC und iPad über Internet")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: "cloud.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    // Option 2: Lokaler Ordner (Files App)
                    Section {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { mode == .local },
                                set: { mode = $0 ? .local : .none }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Wähle einen Ordner aus der Dateien-App (z. B. lokale iCloud oder manuell übertragene Dateien).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Button {
                                    showLocalPicker = true
                                } label: {
                                    Label("Ordner auswählen", systemImage: "folder")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 4)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Lokaler Ordner")
                                        .font(.headline)
                                    Text("Nur auf diesem Gerät, kein automatischer Sync")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Einrichtung")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showLocalPicker) {
            DocumentDirectoryPicker { url in
                store.saveBookmark(for: url)
            }
        }
        .onAppear {
            linkInput = sync.sharingLink
            if !linkInput.isEmpty { mode = .oneDrive }
        }
    }

    private func validateAndContinue() async {
        isValidating = true
        validationError = nil
        let link = linkInput.trimmingCharacters(in: .whitespaces)
        let ok = await sync.validateAndSaveLink(link)
        isValidating = false
        if !ok {
            validationError = "Link konnte nicht verbunden werden. Prüfe ob der Link Schreibrechte hat und das Internet verfügbar ist."
        } else {
            // Create a local temp folder for caching
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("KegelBruederCache", isDirectory: true)
            try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
            store.saveBookmark(for: cacheURL)
        }
    }
}

// MARK: - Document directory picker (for local folder option)

struct DocumentDirectoryPicker: UIViewControllerRepresentable {
    let onSelect: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelect: (URL) -> Void
        init(onSelect: @escaping (URL) -> Void) { self.onSelect = onSelect }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onSelect(url)
        }
    }
}
