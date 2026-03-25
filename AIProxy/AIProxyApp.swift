import SwiftUI

@main
struct AIProxyApp: App {
    @StateObject private var appVM = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appVM)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 620)

        Settings {
            PreferencesView()
                .environmentObject(appVM)
        }
    }
}
