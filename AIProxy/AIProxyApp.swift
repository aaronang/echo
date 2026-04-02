import SwiftUI

@main
struct AIProxyApp: App {
    @StateObject private var appVM = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appVM)
                .frame(minWidth: 500, minHeight: 350)
                .preferredColorScheme(.light)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    appVM.stopAllServers()
                }
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(after: .pasteboard) {
                Button("Copy API URL") {
                    guard let id = appVM.selectedServerID,
                          let config = appVM.servers.first(where: { $0.id == id }) else { return }
                    let url = "http://localhost:\(config.port)"
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            }
        }
    }
}
