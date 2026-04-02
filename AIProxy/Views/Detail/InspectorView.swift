import SwiftUI

struct InspectorView: View {
    @EnvironmentObject var appVM: AppViewModel
    let serverID: UUID

    private var config: ServerConfig {
        appVM.servers.first(where: { $0.id == serverID }) ?? ServerConfig()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("SYSTEM PROMPT")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(config.systemPrompt, forType: .string)
                } label: {
                    Image(systemName: "square.on.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy Prompt")

                Menu("Templates") {
                    ForEach(SystemPromptTemplate.all) { template in
                        Button(template.name) {
                            update(\.systemPrompt, to: template.content)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .font(.caption)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // System prompt editor
            TextEditor(text: Binding(
                get: { config.systemPrompt },
                set: { update(\.systemPrompt, to: $0) }
            ))
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)

            Divider()
                .padding(.top, 8)

            // Options
            VStack(alignment: .leading, spacing: 12) {
                Text("OPTIONS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Toggle(isOn: binding(\.requestLogging)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Request Logging")
                        Text("Log all incoming API requests")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: binding(\.streamPassthrough)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stream Passthrough")
                        Text("Forward SSE streaming responses")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(16)
        }
        .frame(minWidth: 240)
    }

    private func update<T>(_ keyPath: WritableKeyPath<ServerConfig, T>, to value: T) {
        var updated = config
        updated[keyPath: keyPath] = value
        appVM.updateServer(updated)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<ServerConfig, T>) -> Binding<T> {
        Binding(
            get: { config[keyPath: keyPath] },
            set: { update(keyPath, to: $0) }
        )
    }
}
