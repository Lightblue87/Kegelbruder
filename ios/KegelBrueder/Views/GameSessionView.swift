import SwiftUI

struct GameSessionView: View {
    @EnvironmentObject var vm: AppViewModel

    private var winnerName: String? {
        vm.players.max(by: { $0.summe < $1.summe })?.name
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        columnHeader
                        Divider()
                        ForEach($vm.players) { $player in
                            PlayerRowView(player: $player, isWinner: player.name == winnerName)
                                .environmentObject(vm)
                            Divider()
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle("Spielstand")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Spielstand")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.3)
                Text("Runde 4 · \(vm.players.count) Spieler")
                    .font(.system(size: 14))
                    .foregroundColor(.kbTextSecondary)
            }
            Spacer()
            Button {
                vm.activeSheet = .billing
            } label: {
                Label("Abrechnung", systemImage: "eurosign")
            }
            .buttonStyle(KBGlassButton(prominent: true))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("Spieler")
                .frame(width: 130, alignment: .leading)
            Text("Pump")
                .frame(width: 80, alignment: .center)
                .foregroundColor(.kbPumpe)
            Text("9er")
                .frame(width: 80, alignment: .center)
                .foregroundColor(.kbNeuner)
            Text("Kranz")
                .frame(width: 80, alignment: .center)
                .foregroundColor(.kbKranz)
            ForEach(0..<4, id: \.self) { i in
                Text("Rd \(i+1)")
                    .frame(width: 70, alignment: .center)
            }
            Text("Summe")
                .frame(width: 70, alignment: .center)
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundColor(.kbTextSecondary)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemGroupedBackground))
    }
}

struct PlayerRowView: View {
    @EnvironmentObject var vm: AppViewModel
    @Binding var player: Player
    let isWinner: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Name + badge
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(player.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .foregroundColor(isWinner ? .kbBrass500 : .primary)
                    if isWinner {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.kbBrass400)
                    }
                }
                if player.typ == "Gast" {
                    KBPill("Gast", tone: .guest)
                } else if player.offen > 0 {
                    Text(String(format: "Offen %.2f €", player.offen))
                        .font(.system(size: 12))
                        .foregroundColor(.kbDanger)
                }
            }
            .frame(width: 130, alignment: .leading)

            // Pumpen
            CounterCell(value: $player.pumpen, color: .kbPumpe) { delta in
                vm.updatePumpen(playerName: player.name, delta: delta)
            }
            .frame(width: 80)

            // Neuner
            CounterCell(value: $player.neuner, color: .kbNeuner) { delta in
                vm.updateNeuner(playerName: player.name, delta: delta)
            }
            .frame(width: 80)

            // Kranz
            CounterCell(value: $player.kranz, color: .kbKranz) { delta in
                vm.updateKranz(playerName: player.name, delta: delta)
            }
            .frame(width: 80)

            // Rundenfelder
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
                .font(.system(size: 17, weight: .bold))
                .monospacedDigit()
                .foregroundColor(isWinner ? .kbBrass500 : .primary)
        }
        .padding(.vertical, 10)
        .background(isWinner ? Color.kbBrass400.opacity(0.06) : Color.clear)
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
                    .foregroundColor(value > 0 ? color : .kbTextTertiary)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)

            Text("\(value)")
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 22, alignment: .center)
                .foregroundColor(value > 0 ? color : .kbTextTertiary)

            Button {
                onChange(1)
            } label: {
                Image(systemName: "plus.circle")
                    .foregroundColor(color)
                    .font(.system(size: 20))
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
            .font(.system(size: 16))
            .monospacedDigit()
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
                if !focused { text = newVal > 0 ? "\(newVal)" : "" }
            }
            .padding(6)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(8)
    }
}
