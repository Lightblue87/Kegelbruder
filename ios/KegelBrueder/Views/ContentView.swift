import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var store: DataStore

    @State private var selectedItem: String? = nil
    @State private var showAbbruchWarnung = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                Section("Spiel") {
                    if vm.gameRunning {
                        NavigationLink(value: "game") {
                            Label("Laufendes Spiel", systemImage: "figure.bowling")
                        }

                        Button(role: .destructive) {
                            vm.abrechnungStarten()
                        } label: {
                            Label("Abrechnung", systemImage: "eurosign.circle")
                        }

                        Button(role: .destructive) {
                            showAbbruchWarnung = true
                        } label: {
                            Label("Spiel abbrechen", systemImage: "xmark.circle")
                        }
                        .foregroundColor(.red)
                    } else {
                        Button {
                            vm.starteNeuesSpiel()
                        } label: {
                            Label("Neues Spiel", systemImage: "play.circle.fill")
                                .foregroundColor(.kbPrimary)
                                .font(.headline)
                        }
                    }
                }

                Section("Verwaltung") {
                    NavigationLink(value: "cash") {
                        Label("Kassenverwaltung", systemImage: "banknote")
                    }
                    NavigationLink(value: "players") {
                        Label("Spieler verwalten", systemImage: "person.2")
                    }
                    NavigationLink(value: "archive") {
                        Label("Archiv", systemImage: "clock.arrow.circlepath")
                    }
                }

                Section("Einstellungen") {
                    NavigationLink(value: "settings") {
                        Label("Einstellungen", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("Kegel Brüder")
            .listStyle(.insetGrouped)
        } detail: {
            detailView
        }
        .sheet(item: $vm.activeSheet) { sheet in
            sheetView(for: sheet)
        }
        .onChange(of: vm.gameRunning) { _, _ in
            selectedItem = nil   // start → GameSessionView; stop → ReadyScreen
        }
        .alert("Spiel wirklich abbrechen?", isPresented: $showAbbruchWarnung) {
            Button("Abbrechen", role: .cancel) {}
            Button("Ja, abbrechen", role: .destructive) { vm.spielAbbrechen() }
        } message: {
            Text("Alle Punkte und Startgebühren dieses Spiels werden zurückgesetzt. Diese Aktion kann nicht rückgängig gemacht werden.")
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedItem {
        case "game":
            GameSessionView().environmentObject(vm)
        case "cash":
            CashManagementView().environmentObject(vm)
        case "players":
            PlayerManagementView().environmentObject(vm)
        case "archive":
            ArchiveView().environmentObject(vm)
        case "settings":
            SettingsView().environmentObject(vm)
        default:
            if vm.gameRunning {
                GameSessionView().environmentObject(vm)
            } else {
                ReadyScreen { vm.starteNeuesSpiel() }
            }
        }
    }

    @ViewBuilder
    func sheetView(for sheet: AppViewModel.AppSheet) -> some View {
        switch sheet {
        case .attendance:
            AttendanceView().environmentObject(vm)
        case .playerSort:
            PlayerSortView().environmentObject(vm)
        case .game:
            EmptyView()
        case .billing:
            BillingView().environmentObject(vm)
        case .cash:
            CashManagementView().environmentObject(vm)
        case .players:
            PlayerManagementView().environmentObject(vm)
        case .settings:
            SettingsView().environmentObject(vm)
        case .archive:
            ArchiveView().environmentObject(vm)
        case .tiebreak:
            TiebreakView().environmentObject(vm)
        }
    }
}

// MARK: - Ready Screen

struct ReadyScreen: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.kbPrimaryTint)
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.kbPrimary.opacity(0.18), radius: 12, y: 6)
                Image(systemName: "figure.bowling")
                    .font(.system(size: 52))
                    .foregroundColor(.kbPrimary)
            }

            VStack(spacing: 6) {
                Text("Bereit zum Kegeln!")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.3)
                Text("Starte ein neues Spiel, um die Punkteingabe zu öffnen.")
                    .font(.system(size: 16))
                    .foregroundColor(.kbTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                onStart()
            } label: {
                Label("Neues Spiel starten", systemImage: "play.circle.fill")
            }
            .buttonStyle(KBGlassButton(prominent: true))
            .padding(.top, 4)
        }
    }
}
