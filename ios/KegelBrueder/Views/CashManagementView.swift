import SwiftUI

struct CashManagementView: View {
    @EnvironmentObject var vm: AppViewModel

    @State private var betrag: String = ""
    @State private var beschreibung: String = ""
    @State private var gewählterSpieler: String = ""
    @State private var istEinzahlung: Bool = true
    @State private var errorMessage: String? = nil

    var stammMitNamen: [(name: String, schuld: Double)] {
        vm.mitglieder
            .filter { $0.value.typ == "Stamm" && $0.value.offene_zahlung > 0 }
            .map { (name: $0.key, schuld: $0.value.offene_zahlung) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        Form {
            // Kassenstand
            Section {
                KBKassenstandView(betrag: vm.kasse.Kassenstand)
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

                HStack {
                    Text("Betrag (€)")
                    Spacer()
                    TextField("0,00", text: $betrag)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .monospacedDigit()
                }

                TextField("Beschreibung", text: $beschreibung)

                if istEinzahlung {
                    Picker("Spieler (optional)", selection: $gewählterSpieler) {
                        Text("Kein Spieler").tag("")
                        ForEach(stammMitNamen, id: \.name) { item in
                            Text(item.name).tag(item.name)
                        }
                    }
                }

                if let err = errorMessage {
                    Text(err)
                        .foregroundColor(.kbDanger)
                        .font(.caption)
                }

                Button {
                    buchen()
                } label: {
                    HStack {
                        Image(systemName: istEinzahlung ? "plus.circle.fill" : "minus.circle.fill")
                        Text(istEinzahlung ? "Einzahlen" : "Auszahlen")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(istEinzahlung ? .kbSuccess : .kbDanger)
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

    private func buchen() {
        errorMessage = nil
        let cleaned = betrag.replacingOccurrences(of: ",", with: ".")
        guard let b = Double(cleaned), b > 0 else {
            errorMessage = "Bitte einen gültigen Betrag eingeben."
            return
        }

        let bez = beschreibung.trimmingCharacters(in: .whitespaces).isEmpty
            ? (istEinzahlung ? "Einzahlung" : "Auszahlung")
            : beschreibung

        if istEinzahlung {
            vm.einzahlen(betrag: b, beschreibung: bez, spielerName: gewählterSpieler.isEmpty ? nil : gewählterSpieler)
        } else {
            guard b <= vm.kasse.Kassenstand else {
                errorMessage = "Betrag übersteigt den Kassenstand."
                return
            }
            vm.auszahlen(betrag: b, beschreibung: bez)
        }

        betrag = ""
        beschreibung = ""
        gewählterSpieler = ""
    }
}

struct TransactionRow: View {
    let text: String

    var isNegative: Bool { text.contains("| -") }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isNegative ? Color.kbDanger : Color.kbSuccess)
                .frame(width: 8, height: 8)
                .shadow(color: (isNegative ? Color.kbDanger : Color.kbSuccess).opacity(0.4), radius: 3)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(2)
        }
    }
}
