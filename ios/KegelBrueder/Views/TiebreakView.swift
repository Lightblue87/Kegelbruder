import SwiftUI

// Stechen (Tiebreak): sudden-death multi-round until one player leads

struct TiebreakView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var runde: Int = 1
    @State private var inputs: [PlayerInput] = []
    @State private var ergebnis: String? = nil
    @State private var zeigeGleichstandAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                if let ergebnis {
                    ergebnisView(ergebnis)
                } else {
                    eingabeView
                }
            }
            .navigationTitle("Stechen – Runde \(runde)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .onAppear { initialisieren() }
        .alert("Gleichstand – Runde \(runde)", isPresented: $zeigeGleichstandAlert) {
            Button("Nächste Runde") {
                runde += 1
                inputs = inputs.map { PlayerInput(name: $0.name) }
            }
        } message: {
            Text("Alle Spieler haben die gleichen Punkte. Eine weitere Stechen-Runde ist erforderlich.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Text("Gleichstand! Stechen erforderlich.")
                .font(.subheadline)
                .foregroundColor(.kbTextSecondary)
            Text("Spieler: \(inputs.map { $0.name }.joined(separator: ", "))")
                .font(.caption)
                .foregroundColor(.kbTextTertiary)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Input grid

    private var eingabeView: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach($inputs) { $inp in
                    PlayerInputCard(input: $inp)
                }

                Button {
                    auswerten()
                } label: {
                    Label("Runde auswerten", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(KBGlassButton(prominent: true))
                .padding(.top, 8)
            }
            .padding()
        }
    }

    // MARK: - Ergebnis

    private func ergebnisView(_ sieger: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "trophy.fill")
                .font(.system(size: 60))
                .foregroundColor(.kbBrass400)
            Text(sieger)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.kbBrass500)
            Text("hat das Stechen gewonnen!")
                .font(.title3)
                .foregroundColor(.kbTextSecondary)
            Spacer()
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    vm.activeSheet = .billing
                }
            } label: {
                Label("Zur Abrechnung", systemImage: "eurosign.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(KBGlassButton(prominent: true))
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Logic

    private func initialisieren() {
        let namen = vm.getTiedPlayers()
        inputs = namen.map { PlayerInput(name: $0) }
        // Stale Daten eines zuvor abgebrochenen Stechens verwerfen, sonst
        // verfälschen sie die kumulierte Auswertung dieses Stechens.
        // Async, weil onAppear innerhalb des View-Updates läuft und Published-
        // Werte dort nicht synchron geschrieben werden dürfen.
        DispatchQueue.main.async {
            for name in namen { vm.tiebreakExtras[name] = nil }
        }
    }

    private func auswerten() {
        // Accumulate this round's stats into tiebreakExtras
        for inp in inputs {
            let punkte = Int(inp.punkte) ?? 0
            vm.addTiebreakStats(
                name: inp.name,
                pumpen: inp.pumpen,
                neuner: inp.neuner,
                kranz: inp.kranz,
                punkte: punkte
            )
        }

        // Determine winner: highest cumulative punkte, secondary: fewest cumulative pumpen
        let kumuliert: [(name: String, punkte: Int, pumpen: Int)] = inputs.map { inp in
            let extra = vm.tiebreakExtras[inp.name] ?? TiebreakExtra()
            return (name: inp.name, punkte: extra.punkte, pumpen: extra.pumpen)
        }

        let maxPunkte = kumuliert.map { $0.punkte }.max() ?? 0
        let vorne = kumuliert.filter { $0.punkte == maxPunkte }

        if vorne.count == 1 {
            ergebnis = vorne[0].name
        } else {
            // Same punkte — fewer pumpen wins (consistent with resolveRanking)
            let minPumpen = vorne.map { $0.pumpen }.min() ?? 0
            let mitMinPumpen = vorne.filter { $0.pumpen == minPumpen }
            if mitMinPumpen.count == 1 {
                ergebnis = mitMinPumpen[0].name
            } else {
                // Truly tied – require explicit acknowledgment before next round
                zeigeGleichstandAlert = true
            }
        }
    }
}

// MARK: - PlayerInput model

struct PlayerInput: Identifiable {
    let id = UUID()
    var name: String
    var punkte: String = ""
    var pumpen: Int = 0
    var neuner: Int = 0
    var kranz: Int = 0
}

// MARK: - Card per player

struct PlayerInputCard: View {
    @Binding var input: PlayerInput

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(input.name)
                .font(.headline)
                .foregroundColor(.primary)

            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("Punkte")
                        .font(.caption)
                        .foregroundColor(.kbTextSecondary)
                    NumberStringInputField(text: $input.punkte)
                        .frame(width: 70, height: 44)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(10)
                }

                TiebreakCounter(label: "Pump", value: $input.pumpen, color: .kbPumpe)
                TiebreakCounter(label: "9er",  value: $input.neuner, color: .kbNeuner)
                TiebreakCounter(label: "Kranz", value: $input.kranz, color: .kbKranz)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }
}

// MARK: - Counter widget

struct TiebreakCounter: View {
    var label: String
    var value: Binding<Int>
    var color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(color)
            HStack(spacing: 6) {
                Button {
                    if value.wrappedValue > 0 { value.wrappedValue -= 1 }
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundColor(value.wrappedValue > 0 ? color : .kbTextTertiary)
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)

                Text("\(value.wrappedValue)")
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 20, alignment: .center)
                    .foregroundColor(value.wrappedValue > 0 ? color : .kbTextTertiary)

                Button {
                    value.wrappedValue += 1
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundColor(color)
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
