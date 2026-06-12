import SwiftUI

struct BillingView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var rows: [BillingRow] = []
    @State private var gezahlt: [String: String] = [:]
    @State private var showConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Platzierung & Beträge") {
                    ForEach($rows) { $row in
                        BillingRowView(row: $row, gezahlt: $gezahlt)
                    }
                }

                Section("Kassenstand") {
                    LabeledContent("Aktuell") {
                        Text(String(format: "%.2f €", vm.kasse.Kassenstand))
                            .monospacedDigit()
                    }
                    LabeledContent("Bahngebühr") {
                        Text(String(format: "−%.2f €", vm.kasse.Bahngebuehr))
                            .foregroundColor(.kbDanger)
                            .monospacedDigit()
                    }
                    let barZahlungen   = rows.filter { !$0.perKarte }.map { $0.gezahlt }.reduce(0, +)
                    let kartenZahlungen = rows.filter { $0.perKarte }.map { $0.gezahlt }.reduce(0, +)
                    LabeledContent("Einnahmen Bar (Kasse)") {
                        Text(String(format: "+%.2f €", barZahlungen))
                            .foregroundColor(.kbSuccess)
                            .monospacedDigit()
                    }
                    if kartenZahlungen > 0 {
                        LabeledContent("Einnahmen Karte (Konto)") {
                            Text(String(format: "+%.2f €", kartenZahlungen))
                                .foregroundColor(.kbSuccess)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("Abrechnung")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zurück") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Abrechnen") { showConfirm = true }
                        .font(.system(size: 16, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(.kbPrimary)
                }
            }
            .alert("Spiel abrechnen?", isPresented: $showConfirm) {
                Button("Abrechnen", role: .destructive) {
                    vm.abrechnungSpeichern(rows: rows)
                    dismiss()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Das Spiel wird abgerechnet und ins Archiv übertragen. Dieser Schritt kann nicht rückgängig gemacht werden.")
            }
            .onAppear {
                rows = vm.berechneBillingRows()
            }
        }
    }
}

// MARK: - Single billing row

struct BillingRowView: View {
    @Binding var row: BillingRow
    @Binding var gezahlt: [String: String]

    var isWinner: Bool { row.platz == 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Rank + name + points
            HStack(spacing: 8) {
                Text("\(row.platz).")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(isWinner ? .kbBrass500 : .kbTextSecondary)
                    .frame(width: 28, alignment: .leading)
                Text(row.player.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isWinner ? .kbBrass500 : .primary)
                if isWinner {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.kbBrass400)
                }
                Spacer()
                Text("\(row.player.summe) Pkt.")
                    .font(.system(size: 15))
                    .foregroundColor(.kbTextSecondary)
                    .monospacedDigit()
            }

            // Zu zahlen / Gezahlt / Spende
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zu zahlen")
                        .font(.system(size: 12))
                        .foregroundColor(.kbTextSecondary)
                    Text(String(format: "%.2f €", row.zuZahlen))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.kbDanger)
                        .monospacedDigit()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Gezahlt")
                        .font(.system(size: 12))
                        .foregroundColor(.kbTextSecondary)
                    DecimalInputField(text: Binding(
                        get: { gezahlt[row.player.name] ?? "" },
                        set: { val in
                            gezahlt[row.player.name] = val
                            let cleaned = val.replacingOccurrences(of: ",", with: ".")
                            if let d = Double(cleaned) { row.gezahlt = d }
                        }
                    ))
                    .frame(width: 80, height: 32)
                    .padding(6)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(8)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Zahlungsart")
                        .font(.system(size: 12))
                        .foregroundColor(.kbTextSecondary)
                    Picker("Zahlungsart", selection: $row.perKarte) {
                        Text("Bar").tag(false)
                        Text("Karte").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Spende")
                        .font(.system(size: 12))
                        .foregroundColor(.kbTextSecondary)
                    Text(String(format: "%.2f €", max(0, row.gezahlt - row.zuZahlen)))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.kbSuccess)
                        .monospacedDigit()
                }
            }

            // Kostenaufschlüsselung: woraus sich "Zu zahlen" zusammensetzt
            if row.pumpenAnzahl > 0 || row.fremdeNeuner > 0 || row.fremdeKraenze > 0 {
                HStack(spacing: 8) {
                    if row.pumpenAnzahl > 0 {
                        KBPill(String(format: "%d Pump · %.2f €", row.pumpenAnzahl, row.pumpenBetrag), tone: .danger)
                    }
                    if row.fremdeNeuner > 0 {
                        KBPill(String(format: "%d× 9er anderer · %.2f €", row.fremdeNeuner, row.fremdeNeunerBetrag), tone: .primary)
                    }
                    if row.fremdeKraenze > 0 {
                        KBPill(String(format: "%d× Kranz anderer · %.2f €", row.fremdeKraenze, row.fremdeKraenzeBetrag), tone: .success)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .background(isWinner ? Color.kbBrass400.opacity(0.06) : Color.clear)
    }
}
