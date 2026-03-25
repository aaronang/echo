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
            // Header
            headerBar

            Divider()

            // Main content
            HSplitView {
                configPanel
                    .frame(minWidth: 240, maxWidth: 300)

                logPanel
                    .frame(minWidth: 400)
            }

            Divider()

            // Status bar
            StatusBarView(processManager: pm)
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("http://localhost:\(config.port)/generate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            RunningBadge(
                isRunning: pm.isRunning,
                onStart: { appVM.startServer(serverID) },
                onStop: { appVM.stopServer(serverID) }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var configPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ConnectionSection(serverID: serverID)
                    .environmentObject(appVM)
                OptionsSection(serverID: serverID)
                    .environmentObject(appVM)
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var logPanel: some View {
        RequestLogView(processManager: pm)
    }
}
