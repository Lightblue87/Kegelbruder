import SwiftUI

struct AttendanceView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) var dismiss

    // Stamm — default false, set explicitly by the user
    @State private var anwesend: [String: Bool] = [:]
    @State private var zahlungen: [String: String] = [:]

    // Known guests from DB (typ == "Gast") — default false
    @State private var gastAnwesend: [String: Bool] = [:]
    @State private var gastZahlungen: [String: String] = [:]

    // New guests added this session — toggle defaults to true
    @State private var neueGäste: [NeuerGast] = []
    @State private var neuerGastName: String = ""

    var stammMitglieder: [(String, PlayerData)] {
        vm.mitglieder.filter { $0.value.typ == "Stamm" }.sorted { $0.key < $1.key }
    }

    var gastMitglieder: [(String, PlayerData)] {
        vm.mitglieder.filter { $0.value.typ == "Gast" }.sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            Form {
                stammSection
                gästeSection
                übersichtSection
            }
            .navigationTitle("Anwesenheit")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Weiter →") { weiter() }
                        .font(.headline)
                        .disabled(anzahlAnwesend == 0)
                }
            }
            .onAppear { initialisieren() }
        }
    }

    // MARK: - Sections

    private var stammSection: some View {
        Section("Stamm-Mitglieder") {
            ForEach(stammMitglieder, id: \.0) { name, data in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.headline)
                        if data.offene_zahlung > 0 {
                            Text("Offen: \(String(format: "%.2f", data.offene_zahlung)) €")
                                .font(.caption).foregroundColor(.red)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { anwesend[name] ?? false },
                        set: { anwesend[name] = $0 }
                    )).labelsHidden()
                }

                if anwesend[name] ?? false {
                    HStack {
                        Text("Zahlung heute:").foregroundColor(.secondary)
                        Spacer()
                        TextField("0,00", text: Binding(
                            get: { zahlungen[name] ?? "" },
                            set: { zahlungen[name] = $0 }
                        ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        Text("€").foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var gästeSection: some View {
        Section("Gäste") {
            // Known guests from DB
            ForEach(gastMitglieder, id: \.0) { name, data in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.headline)
                        if data.offene_zahlung > 0 {
                            Text("Offen: \(String(format: "%.2f", data.offene_zahlung)) €")
                                .font(.caption).foregroundColor(.red)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { gastAnwesend[name] ?? false },
                        set: { gastAnwesend[name] = $0 }
                    )).labelsHidden()
                }

                if gastAnwesend[name] ?? false {
                    HStack {
                        Text("Zahlung heute:").foregroundColor(.secondary)
                        Spacer()
                        TextField("0,00", text: Binding(
                            get: { gastZahlungen[name] ?? "" },
                            set: { gastZahlungen[name] = $0 }
                        ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        Text("€").foregroundColor(.secondary)
                    }
                }
            }

            // New guests added this session (toggle active by default)
            ForEach($neueGäste) { $gast in
                HStack {
                    Text(gast.name).font(.headline)
                    KBPill("Neu", tone: .guest)
                    Spacer()
                    Toggle("", isOn: $gast.selected).labelsHidden()
                }

                if gast.selected {
                    HStack {
                        Text("Zahlung heute:").foregroundColor(.secondary)
                        Spacer()
                        TextField("0,00", text: $gast.zahlung)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("€").foregroundColor(.secondary)
                    }
                }
            }
            .onDelete { idx in neueGäste.remove(atOffsets: idx) }

            HStack {
                TextField("Neuer Gast", text: $neuerGastName)
                Button("Hinzufügen") {
                    let n = neuerGastName.trimmingCharacters(in: .whitespaces)
                    guard !n.isEmpty else { return }
                    neueGäste.append(NeuerGast(name: n))
                    neuerGastName = ""
                }
                .disabled(neuerGastName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var übersichtSection: some View {
        Section("Übersicht") {
            LabeledContent("Anwesend", value: "\(anzahlAnwesend)")
            LabeledContent(
                "Abwesend (Strafe \(String(format: "%.2f", vm.kasse.Strafe_Stamm)) €)",
                value: "\(stammMitglieder.count - anwesend.filter { $0.value }.count)"
            )
            LabeledContent("Startgeld je Spieler", value: "\(String(format: "%.2f", vm.kasse.Startgeld)) €")
        }
    }

    // MARK: - Helpers

    private var anzahlAnwesend: Int {
        anwesend.filter { $0.value }.count
        + gastAnwesend.filter { $0.value }.count
        + neueGäste.filter { $0.selected }.count
    }

    private func initialisieren() {
        for (name, _) in stammMitglieder {
            if anwesend[name] == nil  { anwesend[name]  = false }
            if zahlungen[name] == nil { zahlungen[name] = "" }
        }
    }

    private func weiter() {
        // 1. Save new guests to DB so berechneStartgebuehren can process their payments
        for gast in neueGäste where vm.mitglieder[gast.name] == nil {
            vm.spielerHinzufügen(name: gast.name, typ: "Gast", offeneZahlung: 0)
        }

        // 2. Merge all attendance and payments
        var allAnwesend = anwesend
        for name in gastMitglieder.map(\.0) where gastAnwesend[name] ?? false {
            allAnwesend[name] = true
        }
        for gast in neueGäste where gast.selected {
            allAnwesend[gast.name] = true
        }

        var parsedZahlungen: [String: Double] = [:]
        for (name, str) in zahlungen          { parsedZahlungen[name] = parse(str) }
        for (name, str) in gastZahlungen
            where gastAnwesend[name] ?? false  { parsedZahlungen[name] = parse(str) }
        for gast in neueGäste where gast.selected {
            parsedZahlungen[gast.name] = parse(gast.zahlung)
        }

        vm.berechneStartgebuehren(anwesend: allAnwesend, zahlungen: parsedZahlungen)

        // 3. Build player lists
        let anwesendeSpieler = stammMitglieder
            .filter { anwesend[$0.0] ?? false }
            .map(\.0)

        let selectedKnownGäste: [Player] = gastMitglieder
            .filter { gastAnwesend[$0.0] ?? false }
            .map { Player(name: $0.0, data: $0.1) }

        let selectedNeueGäste: [Player] = neueGäste
            .filter { $0.selected }
            .map { Player(name: $0.name, typ: "Gast") }

        let alleGäste = selectedKnownGäste + selectedNeueGäste
        vm.pendingAttendees = anwesendeSpieler + alleGäste.map(\.name)
        vm.pendingGäste     = alleGäste

        // 4. Dismiss first, then open PlayerSortView
        //    (dismiss() sets activeSheet = nil; we reassign after the frame completes)
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            vm.activeSheet = .playerSort
        }
    }

    private func parse(_ str: String) -> Double {
        Double(str.replacingOccurrences(of: ",", with: ".")) ?? 0.0
    }
}

private struct NeuerGast: Identifiable {
    let id = UUID()
    var name: String
    var selected: Bool = true
    var zahlung: String = ""
}
