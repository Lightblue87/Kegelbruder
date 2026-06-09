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
                Section("Abrechnung") {
                    ForEach($rows) { $row in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(row.platz).")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .frame(width: 28, alignment: .leading)
                                Text(row.player.name)
                                    .font(.headline)
                                Spacer()
                                Text("\(row.player.summe) Pkt.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Zu zahlen")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(String(format: "%.2f", row.zuZahlen)) €")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.red)
                                }

                                Spacer()

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Gezahlt")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("0,00", text: Binding(
                                        get: { gezahlt[row.player.name] ?? "" },
                                        set: { val in
                                            gezahlt[row.player.name] = val
                                            let cleaned = val.replacingOccurrences(of: ",", with: ".")
                                            if let d = Double(cleaned) {
                                                row.gezahlt = d
                                            }
                                        }
                                    ))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                    .padding(6)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .cornerRadius(6)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Spende")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(String(format: "%.2f", max(0, row.gezahlt - row.zuZahlen))) €")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.green)
                                }
                            }

                            // Penalty detail
                            HStack(spacing: 16) {
                                if row.player.pumpen > 0 {
                                    Label("\(row.player.pumpen) Pump", systemImage: "xmark.circle")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                if row.player.neuner > 0 {
                                    Label("\(row.player.neuner) × 9er", systemImage: "star")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                                if row.player.kranz > 0 {
                                    Label("\(row.player.kranz) Kranz", systemImage: "crown")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Kassenstand") {
                    LabeledContent("Aktuell", value: "\(String(format: "%.2f", vm.kasse.Kassenstand)) €")
                    LabeledContent("Bahngebühr", value: "-\(String(format: "%.2f", vm.kasse.Bahngebuehr)) €")
                    let gesamtZahlungen = rows.map { $0.gezahlt }.reduce(0, +)
                    LabeledContent("Einnahmen", value: "+\(String(format: "%.2f", gesamtZahlungen)) €")
                        .foregroundColor(.green)
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
                        .font(.headline)
                        .buttonStyle(.borderedProminent)
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
