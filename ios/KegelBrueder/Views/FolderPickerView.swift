import SwiftUI
import UniformTypeIdentifiers

struct FolderPickerView: View {
    @EnvironmentObject var store: DataStore
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)

            VStack(spacing: 12) {
                Text("Kegel Brüder")
                    .font(.largeTitle.bold())
                Text("Wähle den OneDrive-Ordner mit den Spielstandsdaten.\nDieser Ordner wird für alle Daten verwendet.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }

            Button {
                showPicker = true
            } label: {
                Label("Ordner auswählen", systemImage: "folder")
                    .font(.title3.bold())
                    .padding()
                    .frame(maxWidth: 300)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }

            Text("Tipp: Navigiere zu OneDrive → Kegelbruder")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .sheet(isPresented: $showPicker) {
            DocumentDirectoryPicker { url in
                store.saveBookmark(for: url)
            }
        }
    }
}

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
