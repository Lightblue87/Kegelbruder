import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vm: AppViewModel
    @StateObject private var sync = SyncManager.shared

    @State private var startgeld: String = ""
    @State private var pumpe: String = ""
    @State private var neuner: String = ""
    @State private var kranz: String = ""
    @State private var strafeStamm: String = ""
    @State private var bahngebuehr: String = ""
    @State private var saved = false

    @State private var linkInput: String = ""
    @State private var isValidating = false
    @State private var linkSaved = false
    @State private var linkError: String? = nil

    var body: some View {
        Form {
            // OneDrive Sync Section
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    // Status
                    HStack(spacing: 8) {
                        if sync.status.isLoading {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: syncStatusIcon)
                                .foregroundColor(syncStatusColor)
                        }
                        Text(sync.status == .idle ? (sync.hasLink ? "Verbunden" : "Kein Link") : sync.status.message)
                            .font(.subheadline)
                            .foregroundColor(syncStatusColor)
                    }

                    TextField("https://1drv.ms/f/s!A...", text: $linkInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.caption)

                    if let err = linkError {
                        Text(err).font(.caption).foregroundColor(.red)
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task { await speichereLink() }
                        } label: {
                            if isValidating {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Text(linkSaved ? "Gespeichert ✓" : "Link speichern")
                            }
                        }
                        .disabled(linkInput.isEmpty || isValidating)
                        .buttonStyle(.bordered)
                        .tint(linkSaved ? .kbSuccess : .kbPrimary)

                        Button {
                            Task { await sync.downloadAll() }
                        } label: {
                            Label("Jetzt sync", systemImage: "arrow.clockwise")
                        }
                        .disabled(!sync.hasLink || sync.status.isLoading)
                        .buttonStyle(.bordered)
                    }

                    if let last = sync.lastSync {
                        Text("Letzter Sync: \(formatLastSync(last))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label("OneDrive Synchronisation", systemImage: "cloud")
            } footer: {
                Text("Freigabelink mit 'Jeder mit dem Link kann bearbeiten'. Internet wird nur zum Sync benötigt.")
            }

            Section("Gebühren") {
                BetragField(label: "Startgeld", value: $startgeld)
                BetragField(label: "Strafe (Abwesend)", value: $strafeStamm)
                BetragField(label: "Bahngebühr", value: $bahngebuehr)
            }

            Section("Strafen & Boni") {
                BetragField(label: "Pumpe (Gutter)", value: $pumpe)
                BetragField(label: "Neuner", value: $neuner)
                BetragField(label: "Kranz", value: $kranz)
            }

            Section {
                Button("Speichern") { speichern() }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)

                if saved {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Gespeichert!")
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .navigationTitle("Kosten Einstellungen")
        .onAppear {
            laden()
            linkInput = sync.sharingLink
        }
    }

    private var syncStatusIcon: String {
        switch sync.status {
        case .idle:    return sync.hasLink ? "checkmark.circle" : "xmark.circle"
        case .syncing: return "arrow.clockwise"
        case .success: return "checkmark.circle.fill"
        case .error:   return "exclamationmark.triangle.fill"
        }
    }

    private var syncStatusColor: Color {
        switch sync.status {
        case .idle:    return sync.hasLink ? .kbSuccess : .kbTextSecondary
        case .syncing: return .kbPrimary
        case .success: return .kbSuccess
        case .error:   return .kbDanger
        }
    }

    private func speichereLink() async {
        isValidating = true
        linkError = nil
        linkSaved = false
        let ok = await sync.validateAndSaveLink(linkInput)
        isValidating = false
        if ok {
            linkSaved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { linkSaved = false }
        } else {
            linkError = "Link ungültig oder kein Schreibzugriff"
        }
    }

    private func formatLastSync(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy HH:mm"
        return f.string(from: date)
    }

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
        k.Strafe_Stamm = parse(strafeStamm) ?? k.Strafe_Stamm
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
            Text("€")
                .foregroundColor(.secondary)
        }
    }
}
