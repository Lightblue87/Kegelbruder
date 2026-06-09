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
                        HStack {
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.secondary)
                            Text(name)
                                .font(.headline)
                            if vm.mitglieder[name]?.typ == "Gast" {
                                Text("Gast")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
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
                        vm.activeSheet = .attendance
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spiel starten") {
                        vm.spielStarten(orderedNames: orderedNames, gäste: vm.pendingGäste)
                        dismiss()
                    }
                    .font(.headline)
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
