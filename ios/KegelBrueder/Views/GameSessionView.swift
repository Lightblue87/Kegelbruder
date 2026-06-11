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
                Text("Runde \(vm.runde) · \(vm.players.count) Spieler")
                    .font(.system(size: 14))
                    .foregroundColor(.kbTextSecondary)
            }
            Spacer()
            Button {
                vm.abrechnungStarten()
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
                } else if player.offene_zahlung > 0 {
                    Text(String(format: "Offen %.2f €", player.offene_zahlung))
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

    var body: some View {
        NumberInputField(value: $value)
            .frame(width: 48, height: 32)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(8)
    }
}

private final class LockedNumberTextField: UITextField {
    var isDark: Bool = false { didSet { if oldValue != isDark { syncInputView() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        super.keyboardType = .numberPad
    }
    required init?(coder: NSCoder) { fatalError() }

    override var keyboardType: UIKeyboardType {
        get { super.keyboardType }
        set { super.keyboardType = .numberPad }
    }

    func syncInputView() {
        if isDark && UIDevice.current.userInterfaceIdiom == .pad {
            let pad = DarkNumberPad(allowsDecimal: false)
            pad.onInsert = { [weak self] s in self?.insertText(s) }
            pad.onDelete = { [weak self] in self?.deleteBackward() }
            inputView = pad
        } else {
            inputView = nil
            super.keyboardAppearance = isDark ? .dark : .default
        }
        if isFirstResponder { reloadInputViews() }
    }

    override func becomeFirstResponder() -> Bool {
        if inputView == nil { super.keyboardAppearance = isDark ? .dark : .default }
        let ok = super.becomeFirstResponder()
        if ok && inputView == nil {
            NotificationCenter.default.addObserver(
                self, selector: #selector(keyboardFullyShown),
                name: UIResponder.keyboardDidShowNotification, object: nil
            )
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        NotificationCenter.default.removeObserver(
            self, name: UIResponder.keyboardDidShowNotification, object: nil
        )
        return super.resignFirstResponder()
    }

    @objc private func keyboardFullyShown() {
        NotificationCenter.default.removeObserver(
            self, name: UIResponder.keyboardDidShowNotification, object: nil
        )
        guard isFirstResponder, inputView == nil else { return }
        super.keyboardType = .numberPad
        super.keyboardAppearance = isDark ? .dark : .default
        reloadInputViews()
    }
}

// UIViewRepresentable wrapper for integer score cells.
// Coordinator.binding is refreshed in updateUIView to avoid writing into a
// stale Player struct capture (Player is a value type; ForEach re-creates
// the binding closure on every vm.players change).
private struct NumberInputField: UIViewRepresentable {
    @Binding var value: Int
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> LockedNumberTextField {
        let f = LockedNumberTextField()
        f.textAlignment      = .center
        f.font               = .monospacedDigitSystemFont(ofSize: 16, weight: .regular)
        f.placeholder        = "0"
        f.autocorrectionType = .no
        f.spellCheckingType  = .no
        f.isDark             = colorScheme == .dark
        f.keyboardAppearance = colorScheme == .dark ? .dark : .default
        f.delegate           = context.coordinator
        return f
    }

    func updateUIView(_ f: LockedNumberTextField, context: Context) {
        context.coordinator.binding = $value
        if !f.isFirstResponder {
            f.text = value > 0 ? "\(value)" : ""
        }
        f.isDark             = colorScheme == .dark
        f.keyboardAppearance = colorScheme == .dark ? .dark : .default
    }

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var binding: Binding<Int>
        init(value: Binding<Int>) { self.binding = value }

        func textFieldShouldBeginEditing(_ f: UITextField) -> Bool {
            f.keyboardType = .numberPad
            return true
        }

        func textFieldDidBeginEditing(_ f: UITextField) {
            f.keyboardType = .numberPad
        }

        func textField(_ tf: UITextField, shouldChangeCharactersIn range: NSRange,
                       replacementString s: String) -> Bool {
            s.isEmpty || s.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
        }

        func textFieldDidEndEditing(_ f: UITextField) {
            let v = f.text.flatMap(Int.init) ?? 0
            binding.wrappedValue = v
            f.text = v > 0 ? "\(v)" : ""
        }

        func textFieldShouldReturn(_ f: UITextField) -> Bool {
            f.resignFirstResponder(); return true
        }
    }
}
