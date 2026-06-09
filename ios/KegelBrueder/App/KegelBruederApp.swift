import SwiftUI

@main
struct KegelBruederApp: App {
    @StateObject private var vm = AppViewModel()
    @StateObject private var store = DataStore.shared

    var body: some Scene {
        WindowGroup {
            if store.folderURL == nil {
                FolderPickerView()
                    .environmentObject(store)
            } else {
                ContentView()
                    .environmentObject(vm)
                    .environmentObject(store)
                    .onAppear {
                        vm.prüfeLockUndStarte {
                            vm.laden()
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                        vm.lockFreigeben()
                    }
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
    }
}
