import SwiftUI

struct PlayerSortView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var orderedNames: [String] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Reihenfolge der Spieler festlegen")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()

                List {
                    ForEach(orderedNames, id: \.self) { name in
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.kbTextTertiary)
                            Text(name)
                                .font(.headline)
                            if vm.pendingGäste.contains(where: { $0.name == name }) {
                                KBPill("Gast", tone: .guest)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { from, to in
                        orderedNames.move(fromOffsets: from, toOffset: to)
                    }
                }
                .environment(\.editMode, .constant(.active))
            }
            .navigationTitle("Spielerreihenfolge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zurück") {
                        vm.rollbackStartgebuehren()
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            vm.activeSheet = .attendance
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spiel starten") {
                        vm.spielStarten(orderedNames: orderedNames, gäste: vm.pendingGäste)
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundColor(.kbPrimary)
                }
            }
            .onAppear { initialisieren() }
        }
    }

    private func initialisieren() {
        guard orderedNames.isEmpty else { return }

        // Try to restore last game order
        let letzte = vm.letzterSpieltag
        let pending = vm.pendingAttendees

        // Use last order as default if players match
        let lastFiltered = letzte.filter { pending.contains($0) }
        let missing = pending.filter { !lastFiltered.contains($0) }
        orderedNames = lastFiltered + missing
    }
}
