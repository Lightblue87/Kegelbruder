import SwiftUI

struct AttendanceView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) var dismiss

    // Stamm members
    @State private var anwesend: [String: Bool] = [:]
    @State private var zahlungen: [String: String] = [:]

    // Guest management
    @State private var gastName: String = ""
    @State private var gäste: [Player] = []

    var stammMitglieder: [(String, PlayerData)] {
        vm.mitglieder
            .filter { $0.value.typ == "Stamm" }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Stamm-Mitglieder") {
                    ForEach(stammMitglieder, id: \.0) { name, data in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name).font(.headline)
                                if data.offene_zahlung > 0 {
                                    Text("Offen: \(String(format: "%.2f", data.offene_zahlung)) €")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { anwesend[name] ?? true },
                                set: { anwesend[name] = $0 }
                            ))
                            .labelsHidden()
                        }

                        if anwesend[name] ?? true {
                            HStack {
                                Text("Zahlung heute:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                TextField("0,00 €", text: Binding(
                                    get: { zahlungen[name] ?? "" },
                                    set: { zahlungen[name] = $0 }
                                ))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                            }
                        }
                    }
                }

                Section("Gäste") {
                    ForEach(gäste) { gast in
                        HStack {
                            Text(gast.name)
                            Spacer()
                            Text("Gast").foregroundColor(.secondary)
                        }
                    }
                    .onDelete { idx in gäste.remove(atOffsets: idx) }

                    HStack {
                        TextField("Gast-Name", text: $gastName)
                        Button("Hinzufügen") {
                            let name = gastName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            gäste.append(Player(name: name, typ: "Gast"))
                            gastName = ""
                        }
                        .disabled(gastName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Übersicht") {
                    let anwesendCount = anwesend.filter { $0.value }.count + gäste.count
                    let abwesendCount = stammMitglieder.count - anwesend.filter { $0.value }.count
                    LabeledContent("Anwesend", value: "\(anwesendCount)")
                    LabeledContent("Abwesend (Strafe \(String(format: "%.2f", vm.kasse.Strafe_Stamm)) €)", value: "\(abwesendCount)")
                    LabeledContent("Startgeld je Spieler", value: "\(String(format: "%.2f", vm.kasse.Startgeld)) €")
                }
            }
            .navigationTitle("Anwesenheit")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Weiter →") { weiter() }
                }
            }
            .onAppear { initialisieren() }
        }
    }

    private func initialisieren() {
        for (name, data) in stammMitglieder {
            if anwesend[name] == nil {
                anwesend[name] = true
            }
            if zahlungen[name] == nil {
                zahlungen[name] = ""
            }
            _ = data
        }
    }

    private func weiter() {
        // Parse payments
        var parsedZahlungen: [String: Double] = [:]
        for (name, str) in zahlungen {
            let cleaned = str.replacingOccurrences(of: ",", with: ".")
            parsedZahlungen[name] = Double(cleaned) ?? 0.0
        }

        vm.berechneStartgebuehren(anwesend: anwesend, zahlungen: parsedZahlungen)

        // Build player list: anwesende Stamm + Gäste
        let anwesendeSpieler = stammMitglieder
            .filter { anwesend[$0.0] ?? true }
            .map { $0.0 }

        // Pass to sort view
        let alle = anwesendeSpieler + gäste.map { $0.name }
        vm.activeSheet = .playerSort

        // Store temporary guest data & ordered list for sort view
        vm.pendingAttendees = alle
        vm.pendingGäste = gäste
        dismiss()
    }
}
