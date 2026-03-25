import SwiftUI

struct OptionsSection: View {
    @EnvironmentObject var appVM: AppViewModel
    let serverID: UUID

    private var config: ServerConfig {
        appVM.servers.first(where: { $0.id == serverID }) ?? ServerConfig()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OPTIONS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Toggle(isOn: binding(\.requestLogging)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Request Logging")
                        .font(.body)
                    Text("Log all incoming API requests")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Toggle(isOn: binding(\.streamPassthrough)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stream Passthrough")
                        .font(.body)
                    Text("Forward SSE streaming responses")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Toggle(isOn: binding(\.autoStart)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-start on Launch")
                        .font(.body)
                    Text("Start this server at login")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<ServerConfig, T>) -> Binding<T> {
        Binding(
            get: { config[keyPath: keyPath] },
            set: { newValue in
                var updated = config
                updated[keyPath: keyPath] = newValue
                appVM.updateServer(updated)
            }
        )
    }
}
