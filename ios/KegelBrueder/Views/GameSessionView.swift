import SwiftUI

struct GameSessionView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    headerRow
                    Divider()
                    ForEach($vm.players) { $player in
                        PlayerRowView(player: $player)
                            .environmentObject(vm)
                        Divider()
                    }
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle("Spielstand")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    vm.activeSheet = .billing
                } label: {
                    Label("Abrechnung", systemImage: "eurosign.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Spieler")
                .frame(width: 130, alignment: .leading)
                .font(.caption.bold())
            Text("Pump")
                .frame(width: 80, alignment: .center)
                .font(.caption.bold())
            Text("9er")
                .frame(width: 80, alignment: .center)
                .font(.caption.bold())
            Text("Kranz")
                .frame(width: 80, alignment: .center)
                .font(.caption.bold())
            ForEach(0..<4, id: \.self) { i in
                Text("Rd \(i+1)")
                    .frame(width: 70, alignment: .center)
                    .font(.caption.bold())
            }
            Text("Summe")
                .frame(width: 70, alignment: .center)
                .font(.caption.bold())
        }
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
}

struct PlayerRowView: View {
    @EnvironmentObject var vm: AppViewModel
    @Binding var player: Player

    var body: some View {
        HStack(spacing: 0) {
            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                if player.typ == "Gast" {
                    Text("Gast")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .frame(width: 130, alignment: .leading)

            // Pumpen
            CounterCell(value: $player.pumpen, color: .red) { delta in
                vm.updatePumpen(playerName: player.name, delta: delta)
            }
            .frame(width: 80)

            // Neuner
            CounterCell(value: $player.neuner, color: .blue) { delta in
                vm.updateNeuner(playerName: player.name, delta: delta)
            }
            .frame(width: 80)

            // Kranz
            CounterCell(value: $player.kranz, color: .green) { delta in
                vm.updateKranz(playerName: player.name, delta: delta)
            }
            .frame(width: 80)

            // Round inputs
            ForEach(0..<4, id: \.self) { runde in
                ScoreCell(
                    value: Binding(
                        get: { player.punkte[runde] },
                        set: { newVal in
                            player.punkte[runde] = newVal
                            vm.updatePunkte(playerName: player.name, runde: runde, wert: newVal)
                        }
                    )
                )
                .frame(width: 70)
            }

            // Summe
            Text("\(player.summe)")
                .frame(width: 70, alignment: .center)
                .font(.headline)
                .foregroundColor(player.summe > 0 ? .primary : .secondary)
        }
        .padding(.vertical, 8)
    }
}

struct CounterCell: View {
    @Binding var value: Int
    var color: Color
    var onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if value > 0 { onChange(-1) }
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundColor(value > 0 ? color : .secondary)
            }
            .buttonStyle(.plain)

            Text("\(value)")
                .font(.headline)
                .frame(minWidth: 20, alignment: .center)
                .foregroundColor(value > 0 ? color : .secondary)

            Button {
                onChange(1)
            } label: {
                Image(systemName: "plus.circle")
                    .foregroundColor(color)
            }
            .buttonStyle(.plain)
        }
    }
}

struct ScoreCell: View {
    @Binding var value: Int
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("0", text: $text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.body)
            .focused($focused)
            .onAppear { text = value > 0 ? "\(value)" : "" }
            .onChange(of: focused) { isFocused in
                if !isFocused {
                    if let v = Int(text), v >= 0 {
                        value = v
                    } else {
                        text = value > 0 ? "\(value)" : ""
                    }
                }
            }
            .onChange(of: value) { newVal in
                if !focused {
                    text = newVal > 0 ? "\(newVal)" : ""
                }
            }
            .padding(6)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(6)
    }
}
