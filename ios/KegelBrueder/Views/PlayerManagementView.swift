import SwiftUI

struct PlayerManagementView: View {
    @EnvironmentObject var vm: AppViewModel

    @State private var showAddSheet = false
    @State private var editingPlayer: (name: String, data: PlayerData)? = nil

    var sortedPlayers: [(String, PlayerData)] {
        vm.mitglieder.sorted { $0.key < $1.key }
    }

    var body: some View {
        List {
            ForEach(sortedPlayers, id: \.0) { name, data in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(name).font(.headline)
                            Text(data.typ)
                                .font(.caption)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(data.typ == "Stamm" ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15))
                                .foregroundColor(data.typ == "Stamm" ? .blue : .orange)
                                .cornerRadius(4)
                        }
                        if data.offene_zahlung > 0 {
                            Text("Offen: \(String(format: "%.2f", data.offene_zahlung)) €")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    Spacer()
                    Button {
                        editingPlayer = (name: name, data: data)
                    } label: {
                        Image(systemName: "pencil.circle")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onDelete { idx in
                let names = sortedPlayers.map { $0.0 }
                idx.forEach { vm.spielerLöschen(name: names[$0]) }
            }
        }
        .navigationTitle("Spieler verwalten")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            PlayerEditSheet(
                titel: "Spieler hinzufügen",
                initialName: "",
                initialTyp: "Stamm",
                initialSchulden: 0.0
            ) { name, typ, schulden in
                vm.spielerHinzufügen(name: name, typ: typ, offeneZahlung: schulden)
            }
        }
        .sheet(item: Binding(
            get: { editingPlayer.map { IdentifiablePlayer(name: $0.name, data: $0.data) } },
            set: { val in editingPlayer = val.map { ($0.name, $0.data) } }
        )) { item in
            PlayerEditSheet(
                titel: "Spieler bearbeiten",
                initialName: item.name,
                initialTyp: item.data.typ,
                initialSchulden: item.data.offene_zahlung
            ) { neuerName, typ, schulden in
                vm.spielerBearbeiten(alterName: item.name, neuerName: neuerName, typ: typ, offeneZahlung: schulden)
            }
        }
    }
}

private struct IdentifiablePlayer: Identifiable {
    var id: String { name }
    let name: String
    let data: PlayerData
}

struct PlayerEditSheet: View {
    let titel: String
    let initialName: String
    let initialTyp: String
    let initialSchulden: Double
    let onSave: (String, String, Double) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var name: String = ""
    @State private var typ: String = "Stamm"
    @State private var schulden: String = ""
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Spielerdaten") {
                    TextField("Name", text: $name)

                    Picker("Typ", selection: $typ) {
                        Text("Stamm").tag("Stamm")
                        Text("Gast").tag("Gast")
                    }
                    .pickerStyle(.segmented)

                    if typ == "Stamm" {
                        HStack {
                            Text("Offener Betrag (€)")
                            Spacer()
                            TextField("0,00", text: $schulden)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                }

                if let err = error {
                    Section {
                        Text(err).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(titel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { speichern() }
                }
            }
            .onAppear {
                name = initialName
                typ = initialTyp
                schulden = initialSchulden > 0 ? String(format: "%.2f", initialSchulden) : ""
            }
        }
    }

    private func speichern() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { error = "Name darf nicht leer sein."; return }
        let cleaned = schulden.replacingOccurrences(of: ",", with: ".")
        let s = Double(cleaned) ?? 0.0
        onSave(n, typ, typ == "Gast" ? 0.0 : s)
        dismiss()
    }
}
