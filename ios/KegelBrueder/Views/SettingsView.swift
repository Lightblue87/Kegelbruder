import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var startgeld: String = ""
    @State private var pumpe: String = ""
    @State private var neuner: String = ""
    @State private var kranz: String = ""
    @State private var strafeStamm: String = ""
    @State private var bahngebuehr: String = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section("Gebühren") {
                BetragField(label: "Startgeld", value: $startgeld)
                BetragField(label: "Strafe (Abwesend)", value: $strafeStamm)
                BetragField(label: "Bahngebühr", value: $bahngebuehr)
            }

            Section("Strafen & Boni") {
                BetragField(label: "Pumpe (Gutter)", value: $pumpe)
                BetragField(label: "Neuner", value: $neuner)
                BetragField(label: "Kranz", value: $kranz)
            }

            Section {
                Button("Speichern") { speichern() }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)

                if saved {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Gespeichert!")
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .navigationTitle("Kosten Einstellungen")
        .onAppear { laden() }
    }

    private func laden() {
        let k = vm.kasse
        startgeld   = fmt(k.Startgeld)
        pumpe       = fmt(k.Pumpe)
        neuner      = fmt(k.Neuner)
        kranz       = fmt(k.Kranz)
        strafeStamm = fmt(k.Strafe_Stamm)
        bahngebuehr = fmt(k.Bahngebuehr)
    }

    private func speichern() {
        var k = vm.kasse
        k.Startgeld    = parse(startgeld)   ?? k.Startgeld
        k.Pumpe        = parse(pumpe)        ?? k.Pumpe
        k.Neuner       = parse(neuner)       ?? k.Neuner
        k.Kranz        = parse(kranz)        ?? k.Kranz
        k.Strafe_Stamm = parse(strafeStamm) ?? k.Strafe_Stamm
        k.Bahngebuehr  = parse(bahngebuehr)  ?? k.Bahngebuehr
        vm.einstellungenSpeichern(k)
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    private func fmt(_ val: Double) -> String { String(format: "%.2f", val) }
    private func parse(_ str: String) -> Double? {
        Double(str.replacingOccurrences(of: ",", with: "."))
    }
}

struct BetragField: View {
    let label: String
    @Binding var value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0,00", text: $value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text("€")
                .foregroundColor(.secondary)
        }
    }
}
