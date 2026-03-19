import SwiftUI

@main
struct AagedalMediaIntelligenceApp: App {
    @StateObject private var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appViewModel)
                .environmentObject(appViewModel.workFolderManager)
                .environmentObject(appViewModel.modelManager)
                .environmentObject(appViewModel.llamaServerManager)
        }
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsView()
                .environmentObject(appViewModel)
                .environmentObject(appViewModel.modelManager)
                .environmentObject(appViewModel.llamaServerManager)
        }
    }
}
