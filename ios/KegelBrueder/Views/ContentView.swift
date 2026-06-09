import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var store: DataStore

    var body: some View {
        NavigationSplitView {
            List {
                Section("Spiel") {
                    if vm.gameRunning {
                        NavigationLink {
                            GameSessionView()
                                .environmentObject(vm)
                        } label: {
                            Label("Laufendes Spiel", systemImage: "figure.bowling")
                        }

                        Button(role: .destructive) {
                            vm.activeSheet = .billing
                        } label: {
                            Label("Abrechnung", systemImage: "eurosign.circle")
                        }

                        Button(role: .destructive) {
                            vm.spielAbbrechen()
                        } label: {
                            Label("Spiel abbrechen", systemImage: "xmark.circle")
                        }
                        .foregroundColor(.red)
                    } else {
                        Button {
                            vm.starteNeuesSpiel()
                        } label: {
                            Label("Neues Spiel", systemImage: "play.circle.fill")
                                .foregroundColor(.accentColor)
                                .font(.headline)
                        }
                    }
                }

                Section("Verwaltung") {
                    NavigationLink {
                        CashManagementView()
                            .environmentObject(vm)
                    } label: {
                        Label("Kassenverwaltung", systemImage: "banknote")
                    }

                    NavigationLink {
                        PlayerManagementView()
                            .environmentObject(vm)
                    } label: {
                        Label("Spieler verwalten", systemImage: "person.2")
                    }

                    NavigationLink {
                        ArchiveView()
                            .environmentObject(vm)
                    } label: {
                        Label("Archiv", systemImage: "clock.arrow.circlepath")
                    }
                }

                Section("Einstellungen") {
                    NavigationLink {
                        SettingsView()
                            .environmentObject(vm)
                    } label: {
                        Label("Kosten Einstellungen", systemImage: "gearshape")
                    }

                    Button {
                        store.folderURL = nil
                        UserDefaults.standard.removeObject(forKey: "dataFolderBookmark")
                    } label: {
                        Label("Ordner ändern", systemImage: "folder.badge.gear")
                    }
                }
            }
            .navigationTitle("Kegel Brüder")
            .listStyle(.insetGrouped)
        } detail: {
            if vm.gameRunning {
                GameSessionView()
                    .environmentObject(vm)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "figure.bowling")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("Bereit zum Kegeln!")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Button("Neues Spiel starten") {
                        vm.starteNeuesSpiel()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(item: $vm.activeSheet) { sheet in
            sheetView(for: sheet)
        }
    }

    @ViewBuilder
    func sheetView(for sheet: AppViewModel.AppSheet) -> some View {
        switch sheet {
        case .attendance:
            AttendanceView()
                .environmentObject(vm)
        case .playerSort:
            PlayerSortView()
                .environmentObject(vm)
        case .game:
            EmptyView()
        case .billing:
            BillingView()
                .environmentObject(vm)
        case .cash:
            CashManagementView()
                .environmentObject(vm)
        case .players:
            PlayerManagementView()
                .environmentObject(vm)
        case .settings:
            SettingsView()
                .environmentObject(vm)
        case .archive:
            ArchiveView()
                .environmentObject(vm)
        case .tiebreak:
            EmptyView()
        }
    }
}
