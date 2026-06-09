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
                            vm.activeSheet = vm.hasTrueTie() ? .tiebreak : .billing
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
                                .foregroundColor(.kbPrimary)
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
                }
            }
            .navigationTitle("Kegel Brüder")
            .listStyle(.insetGrouped)
        } detail: {
            if vm.gameRunning {
                GameSessionView()
                    .environmentObject(vm)
            } else {
                ReadyScreen {
                    vm.starteNeuesSpiel()
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
            TiebreakView()
                .environmentObject(vm)
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
