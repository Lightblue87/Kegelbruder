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

    @State private var transferBetrag: String = ""
    @State private var transferBarZuKonto: Bool = true
    @State private var transferError: String? = nil

    // Transaction date filter
    @State private var vonMonat: Int = 0
    @State private var vonJahr: Int = 0
    @State private var bisMonat: Int = 0
    @State private var bisJahr: Int = 0

    private let monate = ["Jan","Feb","Mär","Apr","Mai","Jun","Jul","Aug","Sep","Okt","Nov","Dez"]

    var stammMitNamen: [(name: String, schuld: Double)] {
        vm.mitglieder
            .filter { $0.value.typ == "Stamm" && $0.value.offene_zahlung > 0 }
            .map { (name: $0.key, schuld: $0.value.offene_zahlung) }
            .sorted { $0.name < $1.name }
    }

    private var txJahre: [Int] {
        Array(Set(vm.kasse.Transaktionen.compactMap { parseDatum($0)?.year })).sorted()
    }

    private var gefilterteTx: [String] {
        Array(vm.kasse.Transaktionen.suffix(200).reversed()).filter { tx in
            guard let d = parseDatum(tx) else { return true }
            if vonMonat > 0 && vonJahr > 0 {
                if d.year < vonJahr || (d.year == vonJahr && d.month < vonMonat) { return false }
            }
            if bisMonat > 0 && bisJahr > 0 {
                if d.year > bisJahr || (d.year == bisJahr && d.month > bisMonat) { return false }
            }
            return true
        }
    }

    private var filterAktiv: Bool {
        (vonMonat > 0 && vonJahr > 0) || (bisMonat > 0 && bisJahr > 0)
    }

    var body: some View {
        KBScreen(maxWidth: 620) {
            KBScreenTitle(title: "Kassenverwaltung")

            // ── Dual balance card ──────────────────────────────────────
            KBGroupBox {
                HStack(spacing: 0) {
                    balanceCell(label: "Kasse (Bar)",
                                betrag: vm.kasse.Kassenstand, color: .kbSuccess)
                    Rectangle()
                        .fill(Color(UIColor.separator))
                        .frame(width: 0.5)
                        .padding(.vertical, 12)
                    balanceCell(label: "Konto",
                                betrag: vm.kasse.Kontostand, color: .kbPrimary)
                }
            }

            // ── Offene Zahlungen ───────────────────────────────────────
            if !stammMitNamen.isEmpty {
                KBGroupBox(header: "Offene Zahlungen") {
                    ForEach(Array(stammMitNamen.enumerated()), id: \.element.name) { i, item in
                        KBRow {
                            Text(item.name).font(.system(size: 17))
                        } trailing: {
                            Text(String(format: "%.2f €", item.schuld))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.kbDanger)
                                .monospacedDigit()
                        }
                        if i < stammMitNamen.count - 1 { KBRowDivider() }
                    }
                }
            }

            // ── Buchung ────────────────────────────────────────────────
            KBGroupBox(header: "Buchung") {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Picker("Art", selection: $istEinzahlung) {
                            Text("Einzahlung").tag(true)
                            Text("Auszahlung").tag(false)
                        }
                        .pickerStyle(.segmented)
                        Picker("Ziel", selection: $istKonto) {
                            Text("Bar").tag(false)
                            Text("Konto").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    KBRowDivider()

                    KBRow {
                        Text("Betrag (€)").font(.system(size: 17))
                    } trailing: {
                        DecimalInputField(text: $betrag)
                            .frame(width: 110, height: 32)
                    }
                    KBRowDivider()

                    if istEinzahlung {
                        KBRow {
                            Text("Spende (€)")
                                .font(.system(size: 17))
                                .foregroundColor(.kbTextSecondary)
                        } trailing: {
                            DecimalInputField(text: $spende)
                                .frame(width: 110, height: 32)
                        }
                        KBRowDivider()

                        if !stammMitNamen.isEmpty {
                            KBRow {
                                Text("Spieler (optional)").font(.system(size: 17))
                            } trailing: {
                                Picker("Spieler", selection: $gewählterSpieler) {
                                    Text("Keiner").tag("")
                                    ForEach(stammMitNamen, id: \.name) { item in
                                        Text(item.name).tag(item.name)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            KBRowDivider()
                        }
                    }

                    HStack {
                        TextField("Beschreibung", text: $beschreibung)
                            .font(.system(size: 17))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundColor(.kbDanger)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }

                    KBRowDivider()

                    Button { buchen() } label: {
                        Label(
                            istEinzahlung ? "Einzahlen" : "Auszahlen",
                            systemImage: istEinzahlung ? "plus.circle.fill" : "minus.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(KBGlassButton(
                        prominent: true,
                        tint: istEinzahlung ? .kbSuccess : .kbDanger
                    ))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }

            // ── Bar ↔ Konto ────────────────────────────────────────────
            KBGroupBox(header: "Bar ↔ Konto") {
                VStack(spacing: 0) {
                    Picker("Richtung", selection: $transferBarZuKonto) {
                        Text("Bar → Konto").tag(true)
                        Text("Konto → Bar").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    KBRowDivider()

                    KBRow {
                        Text("Betrag (€)").font(.system(size: 17))
                    } trailing: {
                        DecimalInputField(text: $transferBetrag)
                            .frame(width: 110, height: 32)
                    }

                    if let err = transferError {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundColor(.kbDanger)
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                    }

                    KBRowDivider()

                    Button { umbuchen() } label: {
                        Label(
                            transferBarZuKonto ? "Bar → Konto umbuchen" : "Konto → Bar umbuchen",
                            systemImage: "arrow.left.arrow.right.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(KBGlassButton(prominent: true, tint: .kbPrimary))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }

            // ── Letzte Transaktionen ───────────────────────────────────
            KBGroupBox(header: "Letzte Transaktionen") {
                VStack(spacing: 0) {
                    // Date filter bar
                    HStack(spacing: 8) {
                        Text("Von").font(.system(size: 13)).foregroundColor(.kbTextSecondary)
                        txDatePicker(monat: $vonMonat, jahr: $vonJahr)
                        Text("Bis").font(.system(size: 13)).foregroundColor(.kbTextSecondary)
                        txDatePicker(monat: $bisMonat, jahr: $bisJahr)
                        Spacer()
                        if filterAktiv {
                            Button {
                                vonMonat = 0; vonJahr = 0
                                bisMonat = 0; bisJahr = 0
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.kbTextSecondary)
                                    .font(.system(size: 16))
                            }
                            .buttonStyle(.plain)
                        }
                        Text("\(gefilterteTx.count)/\(vm.kasse.Transaktionen.count)")
                            .font(.system(size: 12))
                            .foregroundColor(.kbTextTertiary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    KBRowDivider()

                    if gefilterteTx.isEmpty {
                        Text(filterAktiv
                             ? "Keine Transaktionen im gewählten Zeitraum."
                             : "Keine Transaktionen")
                            .font(.system(size: 13))
                            .foregroundColor(.kbTextTertiary)
                            .padding(16)
                    } else {
                        ForEach(Array(gefilterteTx.enumerated()), id: \.offset) { i, tx in
                            HStack(spacing: 10) {
                                let isNeg   = tx.contains("| -")
                                let isKonto = tx.hasPrefix("[Konto]")
                                let dot: Color = isNeg ? .kbDanger : (isKonto ? .kbPrimary : .kbSuccess)
                                Circle()
                                    .fill(dot)
                                    .frame(width: 8, height: 8)
                                    .shadow(color: dot.opacity(0.45), radius: 3)
                                Text(tx)
                                    .font(.system(size: 13))
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            if i < gefilterteTx.count - 1 { KBRowDivider() }
                        }
                    }
                }
            }
        }
        .navigationTitle("Kassenverwaltung")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Sub-views

    private func balanceCell(label: String, betrag: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.kbTextSecondary)
            Text(String(format: "%.2f €", betrag))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(betrag >= 0 ? color : .kbDanger)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func txDatePicker(monat: Binding<Int>, jahr: Binding<Int>) -> some View {
        HStack(spacing: 2) {
            Picker("Monat", selection: monat) {
                Text("–").tag(0)
                ForEach(1...12, id: \.self) { m in Text(monate[m-1]).tag(m) }
            }
            .pickerStyle(.menu)
            .font(.system(size: 13))

            if !txJahre.isEmpty {
                Picker("Jahr", selection: jahr) {
                    Text("–").tag(0)
                    ForEach(txJahre, id: \.self) { y in Text(String(y)).tag(y) }
                }
                .pickerStyle(.menu)
                .font(.system(size: 13))
            }
        }
    }

    // MARK: - Date parsing

    private struct TxDate { let year: Int; let month: Int }

    private func parseDatum(_ tx: String) -> TxDate? {
        let s = tx.hasPrefix("[Konto] ") ? String(tx.dropFirst(8)) : tx
        let parts = s.prefix(10).split(separator: ".")
        guard parts.count == 3,
              let d = Int(parts[0]), d > 0,
              let m = Int(parts[1]),
              let y = Int(parts[2]) else { return nil }
        return TxDate(year: y, month: m)
    }

    // MARK: - Actions (logic unchanged)

    private func buchen() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        errorMessage = nil

        let b  = parseDouble(betrag)
        let sp = parseDouble(spende)

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
                vm.einzahlen(betrag: sp, beschreibung: spendeBesch,
                             spielerName: nil, konto: istKonto)
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

        betrag = ""; spende = ""; beschreibung = ""; gewählterSpieler = ""
    }

    private func umbuchen() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        transferError = nil
        let b = parseDouble(transferBetrag)
        guard b > 0 else {
            transferError = "Bitte einen gültigen Betrag eingeben."
            return
        }
        let source = transferBarZuKonto ? vm.kasse.Kassenstand : vm.kasse.Kontostand
        guard b <= source else {
            transferError = "Betrag übersteigt den \(transferBarZuKonto ? "Kassenstand" : "Kontostand")."
            return
        }
        if transferBarZuKonto { vm.umbuchenBarZuKonto(betrag: b) }
        else                  { vm.umbuchenKontoZuBar(betrag: b) }
        transferBetrag = ""
    }

    private func parseDouble(_ str: String) -> Double {
        Double(str.replacingOccurrences(of: ",", with: ".")) ?? 0.0
    }
}

// MARK: - Transaction row (kept for reuse if needed)

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
