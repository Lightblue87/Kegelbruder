import SwiftUI

struct CashManagementView: View {
    @EnvironmentObject var vm: AppViewModel

    @State private var betrag: String = ""
    @State private var spende: String = ""
    @State private var beschreibung: String = ""
    @State private var gewählterSpieler: String = ""
    @State private var istEinzahlung: Bool = true
    @State private var istKonto: Bool = false
    @State private var errorMessage: String? = nil

    // Transfer section
    @State private var transferBetrag: String = ""
    @State private var transferBarZuKonto: Bool = true
    @State private var transferError: String? = nil

    var stammMitNamen: [(name: String, schuld: Double)] {
        vm.mitglieder
            .filter { $0.value.typ == "Stamm" && $0.value.offene_zahlung > 0 }
            .map { (name: $0.key, schuld: $0.value.offene_zahlung) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        Form {
            // Kassenstand + Kontostand
            Section {
                HStack(spacing: 0) {
                    kontoCard(label: "Kasse (Bar)", betrag: vm.kasse.Kassenstand, color: .kbSuccess)
                    Divider()
                    kontoCard(label: "Konto", betrag: vm.kasse.Kontostand, color: .kbPrimary)
                }
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            // Offene Zahlungen
            if !stammMitNamen.isEmpty {
                Section("Offene Zahlungen") {
                    ForEach(stammMitNamen, id: \.name) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text(String(format: "%.2f €", item.schuld))
                                .foregroundColor(.kbDanger)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                }
            }

            // Buchung
            Section("Buchung") {
                Picker("Art", selection: $istEinzahlung) {
                    Text("Einzahlung").tag(true)
                    Text("Auszahlung").tag(false)
                }
                .pickerStyle(.segmented)

                Picker("Konto", selection: $istKonto) {
                    Text("Bar").tag(false)
                    Text("Konto").tag(true)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Betrag (€)")
                    Spacer()
                    DecimalInputField(text: $betrag)
                        .frame(width: 100, height: 32)
                }

                if istEinzahlung {
                    HStack {
                        Text("Spende (€)")
                            .foregroundColor(.secondary)
                        Spacer()
                        DecimalInputField(text: $spende)
                            .frame(width: 100, height: 32)
                    }

                    Picker("Spieler (optional)", selection: $gewählterSpieler) {
                        Text("Kein Spieler").tag("")
                        ForEach(stammMitNamen, id: \.name) { item in
                            Text(item.name).tag(item.name)
                        }
                    }
                }

                TextField("Beschreibung", text: $beschreibung)

                if let err = errorMessage {
                    Text(err)
                        .foregroundColor(.kbDanger)
                        .font(.caption)
                }

                Button { buchen() } label: {
                    HStack {
                        Image(systemName: istEinzahlung ? "plus.circle.fill" : "minus.circle.fill")
                        Text(istEinzahlung ? "Einzahlen" : "Auszahlen")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(istEinzahlung ? .kbSuccess : .kbDanger)
            }

            // Bar ↔ Konto Transfer
            Section("Bar ↔ Konto") {
                Picker("Richtung", selection: $transferBarZuKonto) {
                    Text("Bar → Konto").tag(true)
                    Text("Konto → Bar").tag(false)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Betrag (€)")
                    Spacer()
                    DecimalInputField(text: $transferBetrag)
                        .frame(width: 100, height: 32)
                }

                if let err = transferError {
                    Text(err)
                        .foregroundColor(.kbDanger)
                        .font(.caption)
                }

                Button { umbuchen() } label: {
                    HStack {
                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                        Text(transferBarZuKonto ? "Bar → Konto" : "Konto → Bar")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.kbPrimary)
            }

            // Transaktionen
            Section("Letzte Transaktionen") {
                let transaktionen = vm.kasse.Transaktionen.suffix(50).reversed()
                if transaktionen.isEmpty {
                    Text("Keine Transaktionen")
                        .foregroundColor(.kbTextSecondary)
                        .italic()
                } else {
                    ForEach(Array(transaktionen.enumerated()), id: \.offset) { _, tx in
                        TransactionRow(text: tx)
                    }
                }
            }
        }
        .navigationTitle("Kassenverwaltung")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Sub-views

    private func kontoCard(label: String, betrag: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.kbTextSecondary)
            Text(String(format: "%.2f €", betrag))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(betrag >= 0 ? color : .kbDanger)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Actions

    private func buchen() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        errorMessage = nil

        let cleanedBetrag = betrag.replacingOccurrences(of: ",", with: ".")
        let b = Double(cleanedBetrag) ?? 0.0
        let cleanedSpende = spende.replacingOccurrences(of: ",", with: ".")
        let sp = Double(cleanedSpende) ?? 0.0

        guard b > 0 || sp > 0 else {
            errorMessage = "Bitte einen gültigen Betrag eingeben."
            return
        }

        let bez = beschreibung.trimmingCharacters(in: .whitespaces).isEmpty
            ? (istEinzahlung ? "Einzahlung" : "Auszahlung")
            : beschreibung

        if istEinzahlung {
            if b > 0 {
                vm.einzahlen(betrag: b, beschreibung: bez,
                             spielerName: gewählterSpieler.isEmpty ? nil : gewählterSpieler,
                             konto: istKonto)
            }
            if sp > 0 {
                let spendeBesch = gewählterSpieler.isEmpty
                    ? "Spende"
                    : "Spende von \(gewählterSpieler)"
                vm.einzahlen(betrag: sp, beschreibung: spendeBesch, spielerName: nil, konto: istKonto)
            }
        } else {
            guard b > 0 else {
                errorMessage = "Bitte einen gültigen Betrag eingeben."
                return
            }
            let balance = istKonto ? vm.kasse.Kontostand : vm.kasse.Kassenstand
            guard b <= balance else {
                errorMessage = "Betrag übersteigt den \(istKonto ? "Kontostand" : "Kassenstand")."
                return
            }
            vm.auszahlen(betrag: b, beschreibung: bez, konto: istKonto)
        }

        betrag = ""
        spende = ""
        beschreibung = ""
        gewählterSpieler = ""
    }

    private func umbuchen() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        transferError = nil
        let cleaned = transferBetrag.replacingOccurrences(of: ",", with: ".")
        guard let b = Double(cleaned), b > 0 else {
            transferError = "Bitte einen gültigen Betrag eingeben."
            return
        }
        let source = transferBarZuKonto ? vm.kasse.Kassenstand : vm.kasse.Kontostand
        guard b <= source else {
            transferError = "Betrag übersteigt den \(transferBarZuKonto ? "Kassenstand" : "Kontostand")."
            return
        }
        if transferBarZuKonto {
            vm.umbuchenBarZuKonto(betrag: b)
        } else {
            vm.umbuchenKontoZuBar(betrag: b)
        }
        transferBetrag = ""
    }
}

struct TransactionRow: View {
    let text: String

    var isNegative: Bool { text.contains("| -") }
    var isKonto: Bool    { text.hasPrefix("[Konto]") }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .shadow(color: dotColor.opacity(0.4), radius: 3)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(2)
        }
    }

    private var dotColor: Color {
        if isNegative { return .kbDanger }
        if isKonto    { return .kbPrimary }
        return .kbSuccess
    }
}
