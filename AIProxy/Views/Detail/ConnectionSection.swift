import SwiftUI

struct ConnectionSection: View {
    @EnvironmentObject var appVM: AppViewModel
    let serverID: UUID

    private var config: ServerConfig {
        appVM.servers.first(where: { $0.id == serverID }) ?? ServerConfig()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CONNECTION")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Provider")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: binding(\.provider)) {
                    ForEach(Provider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
            }

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
