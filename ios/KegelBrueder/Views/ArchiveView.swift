import SwiftUI

struct ArchiveView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var entries: [HistorieEntry] = []
    @State private var selected: HistorieEntry? = nil

    var body: some View {
        NavigationSplitView {
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
            .navigationTitle("Archiv")
            .onAppear {
                entries = vm.store.ladeHistorie().reversed()
            }
        } detail: {
            if let entry = selected {
                ArchiveDetailView(entry: entry)
            } else {
                Text("Spieltag auswählen")
                    .foregroundColor(.secondary)
                    .font(.title2)
            }
        }
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
                    .background(Color(.systemGroupedBackground))

                    Divider()

                    ForEach(rankedPlayers, id: \.1) { platz, name, data in
                        HStack {
                            Text("\(platz).")
                                .frame(width: 36, alignment: .leading)
                                .font(.subheadline.bold())
                                .foregroundColor(platz == 1 ? .yellow : .primary)
                            Text(name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.subheadline)
                            ForEach(0..<4, id: \.self) { i in
                                Text("\(data.punkte.indices.contains(i) ? data.punkte[i] : 0)")
                                    .frame(width: 40, alignment: .center)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Text("\(data.punkte.reduce(0,+))")
                                .frame(width: 44, alignment: .center)
                                .font(.subheadline.bold())
                            Text("\(data.pumpen ?? 0)")
                                .frame(width: 44, alignment: .center)
                                .font(.subheadline)
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
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
                            HStack {
                                Circle()
                                    .fill(tx.contains("| +") || tx.contains("+") ? Color.green.opacity(0.7) : Color.red.opacity(0.7))
                                    .frame(width: 8, height: 8)
                                Text(tx)
                                    .font(.caption)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
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
        .navigationTitle("Spieltag Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
