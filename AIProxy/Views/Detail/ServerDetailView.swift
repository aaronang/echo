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
        .onAppear { checkCli(config.provider) }
        .onChange(of: config.provider) { _, provider in checkCli(provider) }
        .inspector(isPresented: $showInspector) {
            InspectorView(serverID: serverID)
                .environmentObject(appVM)
        }
        .navigationTitle(Binding(
            get: { config.name },
            set: { newName in
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                var updated = config
                updated.name = trimmed
                appVM.updateServer(updated)
            }
        ))
        .navigationSubtitle(pm.isRunning ? "Running on localhost:\(pm.actualPort, format: .number.grouping(.never))" : "Offline")
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
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }
    }

    private func checkCli(_ provider: Provider) {
        guard !ProviderProcess.isAvailable(provider) else { return }
        pm.logWarning("\(provider.rawValue) CLI not found — make sure it is installed and on your PATH")
    }

    private func copyURL() {
        let url = "http://localhost:\(pm.actualPort > 0 ? pm.actualPort : config.port)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    private var providerBinding: Binding<Provider> {
        Binding(
            get: { config.provider },
            set: { newValue in
                pm.logInfo("Model changed to \(newValue.displayName)")
                var updated = config
                updated.provider = newValue
                appVM.updateServer(updated)
            }
        )
    }


}
