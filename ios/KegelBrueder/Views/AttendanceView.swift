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
            HStack(alignment: .top, spacing: 0) {
                // Left: scrollable attendance lists
                Form {
                    stammSection
                    gästeSection
                }

                Divider()

                // Right: always-visible overview panel (no scrolling needed)
                übersichtPanel
                    .frame(width: 280)
                    .background(Color(UIColor.systemGroupedBackground))
            }
            .navigationTitle("Anwesenheit")
            .navigationBarTitleDisplayMode(.inline)
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
            // Prevent accidental dismissal by tapping outside the sheet —
            // all entered attendance data would be lost otherwise.
            .interactiveDismissDisabled()
            .onAppear { initialisieren() }
        }
    }

    // MARK: - Left: Stamm section

    private var stammSection: some View {
        Section("Stamm-Mitglieder") {
            ForEach(stammMitglieder, id: \.0) { name, data in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.headline)
                        schuldenLabel(
                            basis: data.offene_zahlung,
                            istAnwesend: anwesend[name] ?? false
                        )
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
                        DecimalInputField(text: Binding(
                            get: { zahlungen[name] ?? "" },
                            set: { zahlungen[name] = $0 }
                        ))
                        .frame(width: 80, height: 32)
                        Text("€").foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Left: Gäste section

    private var gästeSection: some View {
        Section("Gäste") {
            // Known guests from DB
            ForEach(gastMitglieder, id: \.0) { name, data in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.headline)
                        schuldenLabel(
                            basis: data.offene_zahlung,
                            istAnwesend: gastAnwesend[name] ?? false
                        )
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
                        DecimalInputField(text: Binding(
                            get: { gastZahlungen[name] ?? "" },
                            set: { gastZahlungen[name] = $0 }
                        ))
                        .frame(width: 80, height: 32)
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
                        DecimalInputField(text: $gast.zahlung)
                            .frame(width: 80, height: 32)
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

    // MARK: - Right: Overview panel

    private var übersichtPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                Text("Übersicht")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                // Stats block
                VStack(spacing: 0) {
                    statRow(
                        icon: "person.fill.checkmark",
                        color: .kbSuccess,
                        label: "Anwesend",
                        value: "\(anzahlAnwesend)"
                    )
                    Divider().padding(.leading, 44)
                    statRow(
                        icon: "person.fill.xmark",
                        color: .kbDanger,
                        label: "Abwesend",
                        value: "\(anzahlAbwesend)"
                    )
                    Divider().padding(.leading, 44)
                    statRow(
                        icon: "eurosign.circle",
                        color: .kbPrimary,
                        label: "Startgeld/Spieler",
                        value: String(format: "%.2f €", vm.kasse.Startgeld)
                    )
                    Divider().padding(.leading, 44)
                    statRow(
                        icon: "exclamationmark.circle",
                        color: .orange,
                        label: "Strafe Abwesend",
                        value: String(format: "%.2f €", vm.kasse.Strafe_Stamm)
                    )
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal, 16)

                if anzahlAnwesend > 0 {
                    // Total start fees
                    let total = Double(anzahlAnwesend) * vm.kasse.Startgeld
                    HStack {
                        Text("Startgelder gesamt")
                            .font(.subheadline)
                            .foregroundColor(.kbTextSecondary)
                        Spacer()
                        Text(String(format: "%.2f €", total))
                            .font(.subheadline.bold())
                            .foregroundColor(.kbPrimary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    // Attending player list
                    Text("Spieler heute")
                        .font(.subheadline.bold())
                        .foregroundColor(.kbTextSecondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        .padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(anwesendeNamen, id: \.self) { name in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.kbSuccess)
                                    .font(.system(size: 14))
                                Text(name)
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            if name != anwesendeNamen.last {
                                Divider().padding(.leading, 38)
                            }
                        }
                    }
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 20)
            }
        }
    }

    private func statRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 18))
                .frame(width: 28, alignment: .center)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private var anzahlAnwesend: Int {
        anwesend.filter { $0.value }.count
        + gastAnwesend.filter { $0.value }.count
        + neueGäste.filter { $0.selected }.count
    }

    private var anzahlAbwesend: Int {
        stammMitglieder.count - anwesend.filter { $0.value }.count
    }

    private var anwesendeNamen: [String] {
        let stamm = stammMitglieder.filter { anwesend[$0.0] ?? false }.map(\.0)
        let gastDB = gastMitglieder.filter { gastAnwesend[$0.0] ?? false }.map(\.0)
        let gastNeu = neueGäste.filter { $0.selected }.map(\.name)
        return (stamm + gastDB + gastNeu).sorted()
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
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            vm.activeSheet = .playerSort
        }
    }

    @ViewBuilder
    private func schuldenLabel(basis: Double, istAnwesend: Bool) -> some View {
        if istAnwesend {
            let gesamt = basis + vm.kasse.Startgeld
            Text("Offen inkl. Startgeld: \(String(format: "%.2f", gesamt)) €")
                .font(.caption).foregroundColor(.red)
        } else if basis > 0 {
            Text("Offen: \(String(format: "%.2f", basis)) €")
                .font(.caption).foregroundColor(.red)
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
