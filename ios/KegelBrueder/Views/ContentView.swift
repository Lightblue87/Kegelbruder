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
                            Label {
                                Text("Laufendes Spiel")
                            } icon: {
                                KBSidebarIcon(systemName: "circle.dotted", tint: .kbPrimary)
                            }
                        }

                        Button {
                            vm.abrechnungStarten()
                        } label: {
                            Label {
                                Text("Abrechnung")
                            } icon: {
                                KBSidebarIcon(systemName: "eurosign.circle", tint: .kbSuccess)
                            }
                        }

                        Button(role: .destructive) {
                            showAbbruchWarnung = true
                        } label: {
                            Label {
                                Text("Spiel abbrechen")
                                    .foregroundColor(.kbDanger)
                            } icon: {
                                KBSidebarIcon(systemName: "xmark.circle", tint: .kbDanger)
                            }
                        }
                    } else {
                        Button {
                            vm.starteNeuesSpiel()
                        } label: {
                            Label {
                                Text("Neues Spiel")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.kbPrimary)
                            } icon: {
                                KBSidebarIcon(systemName: "play.circle.fill", tint: .kbPrimary)
                            }
                        }
                    }
                }

                Section("Verwaltung") {
                    NavigationLink(value: "cash") {
                        Label {
                            Text("Kassenverwaltung")
                        } icon: {
                            KBSidebarIcon(systemName: "banknote", tint: .kbSuccess)
                        }
                    }
                    NavigationLink(value: "players") {
                        Label {
                            Text("Spieler verwalten")
                        } icon: {
                            KBSidebarIcon(systemName: "person.2", tint: .kbNeuner)
                        }
                    }
                    NavigationLink(value: "archive") {
                        Label {
                            Text("Archiv")
                        } icon: {
                            KBSidebarIcon(systemName: "clock.arrow.circlepath", tint: Color(.systemGray))
                        }
                    }
                    NavigationLink(value: "settings") {
                        Label {
                            Text("Einstellungen")
                        } icon: {
                            KBSidebarIcon(systemName: "gearshape", tint: Color(.systemGray2))
                        }
                    }
                }
            }
            .navigationTitle("Kegel Brüder")
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
        } detail: {
            detailView
                .background(KBAppBackground())
        }
        .background(KBAppBackground())
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
        .alert("Archivierungsfehler", isPresented: Binding(
            get: { vm.archivFehler != nil },
            set: { if !$0 { vm.archivFehler = nil } }
        )) {
            Button("OK") { vm.archivFehler = nil }
        } message: {
            Text(vm.archivFehler ?? "")
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
        case .pumpenStechen:
            PumpenTiebreakView().environmentObject(vm)
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
