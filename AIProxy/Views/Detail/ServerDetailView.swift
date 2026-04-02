import SwiftUI

struct ServerDetailView: View {
    @EnvironmentObject var appVM: AppViewModel
    let serverID: UUID

    var body: some View {
        ServerDetailContent(
            serverID: serverID,
            pm: appVM.processManager(for: serverID)
        )
        .environmentObject(appVM)
    }
}

private struct ServerDetailContent: View {
    @EnvironmentObject var appVM: AppViewModel
    let serverID: UUID
    @ObservedObject var pm: ProcessManager

    @AppStorage("showInspector") private var showInspector = true

    private var config: ServerConfig {
        appVM.servers.first(where: { $0.id == serverID }) ?? ServerConfig()
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            RequestLogView(processManager: pm)
            Divider()
            StatusBarView(processManager: pm)
        }
        .inspector(isPresented: $showInspector) {
            InspectorView(serverID: serverID)
                .environmentObject(appVM)
        }
        .navigationTitle(config.name)
        .navigationSubtitle(pm.isRunning ? "Running on localhost:\(config.port, format: .number.grouping(.never))" : "Offline")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("", selection: providerBinding) {
                    ForEach(Provider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(pm.isRunning)

                if pm.isRunning {
                    Button {
                        appVM.restartServer(serverID)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }

                    Button {
                        appVM.stopServer(serverID)
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                } else {
                    Button {
                        appVM.startServer(serverID)
                    } label: {
                        Image(systemName: "play.fill")
                    }
                }

                Button {
                    showInspector.toggle()
                } label: {
                    Image(systemName: "person.text.rectangle")
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }
    }

    private func copyURL() {
        let url = "http://localhost:\(config.port)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    private var providerBinding: Binding<Provider> {
        Binding(
            get: { config.provider },
            set: { newValue in
                var updated = config
                updated.provider = newValue
                appVM.updateServer(updated)
            }
        )
    }


}
