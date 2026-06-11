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
    // Local accumulator — intentionally NOT written to vm.tiebreakExtras so that
    // Pumpenstechen data doesn't contaminate the Punktestechen check in getTiedPlayers().
    @State private var pumpExtras: [String: Int] = [:]

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
        for inp in inputs {
            pumpExtras[inp.name, default: 0] += Int(inp.punkte) ?? 0
        }

        let maxPts = pumpExtras.values.max() ?? 0
        let minPts = pumpExtras.values.min() ?? 0

        if maxPts != minPts {
            let ordered = pumpExtras.sorted { $0.value > $1.value }.map { $0.key }
            vm.setPumpRank(ordered: ordered)
            aufgelöst = true
        } else {
            runde += 1
            inputs = inputs.map { PlayerInput(name: $0.name) }
        }
    }
}
