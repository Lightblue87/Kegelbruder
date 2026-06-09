import SwiftUI

@main
struct KegelBruederApp: App {
    @StateObject private var vm    = AppViewModel()
    @StateObject private var store = DataStore.shared
    @StateObject private var sync  = SyncManager.shared

    @AppStorage("appColorScheme") private var colorSchemeRaw: Int = 0
    @Environment(\.scenePhase) private var scenePhase

    private var preferredColorScheme: ColorScheme? {
        switch colorSchemeRaw {
        case 1: return .dark
        case 2: return .light
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !store.isReady {
                    // iCloud container wird aufgelöst – kurzer Ladebildschirm
                    iCloudLoadingView()
                } else {
                    ContentView()
                        .environmentObject(vm)
                        .environmentObject(store)
                        .environmentObject(sync)
                        .preferredColorScheme(preferredColorScheme)
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
                    await store.setUp()
                    sync.startMonitoring()
                    vm.prüfeLockUndStarte { vm.laden() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    if store.iCloudAvailable {
                        store.reloadDatabase()
                        vm.laden()
                    }
                case .background:
                    break // iCloud syncs automatically
                default:
                    break
                }
            }
        }
    }
}

// MARK: - Loading screen while iCloud resolves

private struct iCloudLoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.bowling")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            Text("Kegel Brüder")
                .font(.largeTitle.bold())
            HStack(spacing: 10) {
                ProgressView()
                Text("iCloud Drive wird verbunden…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}
