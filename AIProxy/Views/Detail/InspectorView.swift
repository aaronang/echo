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
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

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
