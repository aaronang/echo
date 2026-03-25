import SwiftUI

@main
struct AIProxyApp: App {
    @StateObject private var appVM = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appVM)
                .frame(minWidth: 500, minHeight: 350)
                .navigationTitle("")
        }
        .defaultSize(width: 1000, height: 650)

        Settings {
            PreferencesView()
                .environmentObject(appVM)
        }
    }
}
