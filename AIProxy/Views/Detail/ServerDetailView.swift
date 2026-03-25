import SwiftUI

struct ServerDetailView: View {
    @EnvironmentObject var appVM: AppViewModel
    let serverID: UUID

    private var config: ServerConfig {
        appVM.servers.first(where: { $0.id == serverID }) ?? ServerConfig()
    }

    private var pm: ProcessManager {
        appVM.processManager(for: serverID)
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsRow
            Divider()
            RequestLogView(processManager: pm)
            Divider()
            StatusBarView(processManager: pm)
        }
        .navigationTitle(config.name)
        .navigationSubtitle("http://localhost:" + String(config.port) + "/generate")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                RunningBadge(
                    isRunning: pm.isRunning,
                    onStart: { appVM.startServer(serverID) },
                    onStop: { appVM.stopServer(serverID) }
                )
            }
        }
    }

    private var settingsRow: some View {
        HStack(alignment: .top, spacing: 0) {
            ConnectionSection(serverID: serverID)
                .environmentObject(appVM)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .padding(.vertical, 4)

            OptionsSection(serverID: serverID)
                .environmentObject(appVM)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

}
