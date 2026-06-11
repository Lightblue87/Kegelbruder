import SwiftUI

// Pumpenstechen: run before Punktestechen to resolve ties among the most-pumpen players.
// Winner (highest cumulative punkte in the stechen round) gets the best pump rank.
// The pump rank is then used to sort players within any tied-points groups.

struct PumpenTiebreakView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var runde: Int = 1
    @State private var inputs: [PlayerInput] = []
    @State private var aufgelöst: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                if aufgelöst {
                    weiterView
                } else {
                    eingabeView
                }
            }
            .navigationTitle("Pumpenstechen – Runde \(runde)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .onAppear { initialisieren() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Text("Gleichstand bei Pumpen! Pumpenstechen erforderlich.")
                .font(.subheadline)
                .foregroundColor(.kbTextSecondary)
                .multilineTextAlignment(.center)
            Text("Spieler: \(inputs.map { $0.name }.joined(separator: ", "))")
                .font(.caption)
                .foregroundColor(.kbTextTertiary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal)
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

    // MARK: - After resolution

    private var weiterView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.kbSuccess)
            Text("Pumpenstechen aufgelöst")
                .font(.system(size: 28, weight: .bold))
            Spacer()
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    vm.activeSheet = vm.hasTrueTie() ? .tiebreak : .billing
                }
            } label: {
                Label("Weiter", systemImage: "arrow.right.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(KBGlassButton(prominent: true))
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Logic

    private func initialisieren() {
        inputs = vm.getPumpTiedPlayers().map { PlayerInput(name: $0) }
    }

    private func auswerten() {
        // Accumulate this round's stats
        for inp in inputs {
            vm.addTiebreakStats(
                name: inp.name,
                pumpen: inp.pumpen,
                neuner: inp.neuner,
                kranz:  inp.kranz,
                punkte: Int(inp.punkte) ?? 0
            )
        }

        // Build cumulative punkte table
        let kum: [(name: String, punkte: Int)] = inputs.map { inp in
            let extra = vm.tiebreakExtras[inp.name] ?? TiebreakExtra()
            return (inp.name, extra.punkte)
        }

        let maxPts = kum.map { $0.punkte }.max() ?? 0
        let minPts = kum.map { $0.punkte }.min() ?? 0

        if maxPts != minPts {
            // Resolved: order highest→lowest; winner gets pump rank 0
            let ordered = kum.sorted { $0.punkte > $1.punkte }.map { $0.name }
            vm.setPumpRank(ordered: ordered)
            aufgelöst = true
        } else {
            // Still tied — another round
            runde += 1
            inputs = inputs.map { PlayerInput(name: $0.name) }
        }
    }
}
