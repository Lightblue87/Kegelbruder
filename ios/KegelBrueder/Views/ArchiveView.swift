import SwiftUI

struct ArchiveView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var entries: [HistorieEntry] = []
    @State private var selected: HistorieEntry? = nil

    var body: some View {
        NavigationSplitView {
            Group {
                if entries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("Noch keine Spiele archiviert")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Gespiele werden nach der Abrechnung hier gespeichert.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(entries, selection: $selected) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.datum)
                                .font(.headline)
                            HStack {
                                Label("\(entry.players.count) Spieler", systemImage: "person.2")
                                Spacer()
                                Label("\(entry.transaktionen.count) Buchungen", systemImage: "list.bullet")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .tag(entry)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(KBAppBackground())
            .navigationTitle("Archiv")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { laden() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear { laden() }
        } detail: {
            if let entry = selected {
                ArchiveDetailView(entry: entry)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 44))
                        .foregroundColor(.kbTextSecondary)
                    Text("Spieltag auswählen")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.kbTextSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(KBAppBackground())
            }
        }
    }

    private func laden() {
        entries = Array(vm.store.ladeHistorie().reversed())
    }
}

struct ArchiveDetailView: View {
    let entry: HistorieEntry

    var rankedPlayers: [(Int, String, PlayerData)] {
        let order = entry.spieler_reihenfolge ?? Array(entry.players.keys).sorted()
        let players = order.compactMap { name -> (String, PlayerData)? in
            entry.players[name].map { (name, $0) }
        }
        let sorted = players.sorted { $0.1.punkte.reduce(0,+) > $1.1.punkte.reduce(0,+) }
        return sorted.enumerated().map { (i, p) in (i + 1, p.0, p.1) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(entry.datum)
                    .font(.largeTitle.bold())
                    .padding(.horizontal)

                // Placement table
                VStack(spacing: 0) {
                    HStack {
                        Text("Pl.").frame(width: 36, alignment: .leading).font(.caption.bold())
                        Text("Spieler").frame(maxWidth: .infinity, alignment: .leading).font(.caption.bold())
                        Text("Rd1").frame(width: 40, alignment: .center).font(.caption.bold())
                        Text("Rd2").frame(width: 40, alignment: .center).font(.caption.bold())
                        Text("Rd3").frame(width: 40, alignment: .center).font(.caption.bold())
                        Text("Rd4").frame(width: 40, alignment: .center).font(.caption.bold())
                        Text("Σ").frame(width: 44, alignment: .center).font(.caption.bold())
                        Text("Pump").frame(width: 44, alignment: .center).font(.caption.bold())
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(.regularMaterial)

                    Divider()

                    ForEach(rankedPlayers, id: \.1) { platz, name, data in
                        HStack {
                            Text("\(platz).")
                                .frame(width: 36, alignment: .leading)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(platz == 1 ? .kbBrass500 : .kbTextSecondary)
                            Text(name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.system(size: 15, weight: platz == 1 ? .semibold : .regular))
                                .foregroundColor(platz == 1 ? .kbBrass500 : .primary)
                            ForEach(0..<4, id: \.self) { i in
                                Text("\(data.punkte.indices.contains(i) ? data.punkte[i] : 0)")
                                    .frame(width: 40, alignment: .center)
                                    .font(.system(size: 14))
                                    .foregroundColor(.kbTextSecondary)
                                    .monospacedDigit()
                            }
                            Text("\(data.punkte.reduce(0,+))")
                                .frame(width: 44, alignment: .center)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(platz == 1 ? .kbBrass500 : .primary)
                                .monospacedDigit()
                            Text("\(data.pumpen ?? 0)")
                                .frame(width: 44, alignment: .center)
                                .font(.system(size: 14))
                                .foregroundColor(.kbPumpe)
                                .monospacedDigit()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(platz == 1 ? Color.kbBrass400.opacity(0.07) : Color.clear)
                        Divider()
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                // Transactions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transaktionen")
                        .font(.headline)
                        .padding(.horizontal)

                    VStack(spacing: 0) {
                        ForEach(Array(entry.transaktionen.enumerated()), id: \.offset) { _, tx in
                            HStack(spacing: 10) {
                                let isNeg = tx.contains("| -")
                                Circle()
                                    .fill(isNeg ? Color.kbDanger : Color.kbSuccess)
                                    .frame(width: 8, height: 8)
                                Text(tx)
                                    .font(.system(size: 13))
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 5)
                            Divider()
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(KBAppBackground())
        .navigationTitle("Spieltag Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
