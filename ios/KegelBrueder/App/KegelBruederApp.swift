import SwiftUI

@main
struct KegelBruederApp: App {
    @StateObject private var vm = AppViewModel()
    @StateObject private var store = DataStore.shared
    @StateObject private var sync = SyncManager.shared

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if store.folderURL == nil && !sync.hasLink {
                    FolderPickerView()
                        .environmentObject(store)
                } else {
                    ContentView()
                        .environmentObject(vm)
                        .environmentObject(store)
                        .environmentObject(sync)
                        .alert("App bereits geöffnet", isPresented: $vm.showLockWarning) {
                            Button("Übernehmen", role: .destructive) {
                                vm.onLockOverride?()
                                vm.showLockWarning = false
                            }
                            Button("Abbrechen", role: .cancel) {
                                vm.showLockWarning = false
                            }
                        } message: {
                            Text("Die App ist bereits geöffnet auf:\n\nGerät: \(vm.lockWarningGerät)\nSeit: \(vm.lockWarningSeit)\n\nMöchtest du den Zugriff übernehmen?")
                        }
                }
            }
            .onAppear {
                Task {
                    // Beim Start: zuerst Daten von OneDrive laden, dann Lock prüfen
                    if sync.hasLink {
                        await sync.downloadAll()
                    }
                    vm.prüfeLockUndStarte { vm.laden() }
                }
            }
            .onChange(of: scenePhase) { phase in
                switch phase {
                case .background:
                    // Beim in den Hintergrund gehen: hochladen
                    if sync.hasLink {
                        Task { await sync.uploadAll(from: store) }
                    }
                case .active:
                    // Beim Wiederkommen: herunterladen
                    if sync.hasLink {
                        Task {
                            await sync.downloadAll()
                            vm.laden()
                        }
                    }
                default:
                    break
                }
            }
        }
    }
}
