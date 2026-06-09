import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var vm: AppViewModel
    @StateObject private var sync  = SyncManager.shared
    @StateObject private var store = DataStore.shared

    @AppStorage("appColorScheme")  private var colorSchemeRaw: Int    = 0
    // Persisted across launches so the user doesn't have to re-paste the link
    @AppStorage("savedICloudLink") private var iCloudLink: String     = ""

    @State private var showFolderPicker = false
    @State private var startgeld:   String = ""
    @State private var pumpe:       String = ""
    @State private var neuner:      String = ""
    @State private var kranz:       String = ""
    @State private var strafeStamm: String = ""
    @State private var bahngebuehr: String = ""
    @State private var saved = false

    var body: some View {
        Form {
            Group {
                Section {
                    // ── Step 1: Paste the iCloud share link ──────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Text("iCloud Freigabe-Link")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            TextField("https://www.icloud.com/iclouddrive/…",
                                      text: $iCloudLink)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.footnote)
                            Button {
                                openICloudLink()
                            } label: {
                                Text("Öffnen")
                                    .font(.footnote.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(iCloudLink.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(.vertical, 2)

                    // ── Step 2: Pick the shared folder once ──────────────────
                    Button {
                        showFolderPicker = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "folder.badge.plus")
                                .foregroundColor(.kbPrimary)
                            Text("Freigegebenen Ordner wählen")
                                .foregroundColor(.kbPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    // ── Status after folder is selected ──────────────────────
                    if store.iCloudAvailable {
                        HStack(spacing: 10) {
                            Image(systemName: store.writeAccessOK
                                  ? "checkmark.shield.fill"
                                  : "xmark.shield.fill")
                                .foregroundColor(store.writeAccessOK ? .kbSuccess : .kbDanger)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.folderName)
                                    .font(.subheadline.bold())
                                Text(store.writeAccessOK
                                     ? "Lese- & Schreibzugriff bestätigt"
                                     : "Kein Schreibzugriff – Ordner prüfen")
                                    .font(.caption)
                                    .foregroundColor(store.writeAccessOK ? .kbSuccess : .kbDanger)
                            }
                            Spacer()
                            Button {
                                Task { await sync.downloadAll(); vm.laden() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .disabled(sync.status.isLoading || !store.writeAccessOK)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Label("Datenbankordner", systemImage: "externaldrive.connected.to.line.below")
                } footer: {
                    if store.iCloudAvailable {
                        Text(store.dbPath)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("1. Link aus iCloud Drive einfügen → „Öffnen" tippt den Ordner in der Files-App an.\n2. Zurück zur App → „Freigegebenen Ordner wählen" → Ordner antippen → fertig.\nDer Zugriff wird einmalig erteilt und danach automatisch wiederhergestellt.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Erscheinungsbild") {
                    Picker("Darstellung", selection: $colorSchemeRaw) {
                        Text("Systemeinstellung").tag(0)
                        Text("Hell").tag(2)
                        Text("Dunkel").tag(1)
                    }
                }
            }

            Group {
                Section("Gebühren") {
                    BetragField(label: "Startgeld",          value: $startgeld)
                    BetragField(label: "Strafe (Abwesend)",  value: $strafeStamm)
                    BetragField(label: "Bahngebühr",         value: $bahngebuehr)
                }

                Section("Strafen & Boni") {
                    BetragField(label: "Pumpe (Gutter)", value: $pumpe)
                    BetragField(label: "Neuner",         value: $neuner)
                    BetragField(label: "Kranz",          value: $kranz)
                }

                Section {
                    Button("Speichern") { speichern() }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)

                    if saved {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("Gespeichert!").foregroundColor(.green)
                        }
                    }
                }
            }
        }
        .navigationTitle("Einstellungen")
        .onAppear { laden() }
        .sheet(isPresented: $showFolderPicker) {
            DocumentDirectoryPicker { url in
                store.saveBookmark(for: url)
                vm.laden()
                showFolderPicker = false
            }
        }
    }

    // MARK: - Actions

    private func openICloudLink() {
        let trimmed = iCloudLink.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), url.scheme != nil else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Helpers

    private func laden() {
        let k = vm.kasse
        startgeld   = fmt(k.Startgeld)
        pumpe       = fmt(k.Pumpe)
        neuner      = fmt(k.Neuner)
        kranz       = fmt(k.Kranz)
        strafeStamm = fmt(k.Strafe_Stamm)
        bahngebuehr = fmt(k.Bahngebuehr)
    }

    private func speichern() {
        var k = vm.kasse
        k.Startgeld    = parse(startgeld)   ?? k.Startgeld
        k.Pumpe        = parse(pumpe)        ?? k.Pumpe
        k.Neuner       = parse(neuner)       ?? k.Neuner
        k.Kranz        = parse(kranz)        ?? k.Kranz
        k.Strafe_Stamm = parse(strafeStamm)  ?? k.Strafe_Stamm
        k.Bahngebuehr  = parse(bahngebuehr)  ?? k.Bahngebuehr
        vm.einstellungenSpeichern(k)
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    private func fmt(_ val: Double) -> String { String(format: "%.2f", val) }
    private func parse(_ str: String) -> Double? {
        Double(str.replacingOccurrences(of: ",", with: "."))
    }
}

// MARK: - BetragField

struct BetragField: View {
    let label: String
    @Binding var value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0,00", text: $value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text("€").foregroundColor(.secondary)
        }
    }
}
