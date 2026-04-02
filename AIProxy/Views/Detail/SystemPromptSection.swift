import SwiftUI

struct SystemPromptSection: View {
    @EnvironmentObject var appVM: AppViewModel
    let serverID: UUID

    private var config: ServerConfig {
        appVM.servers.first(where: { $0.id == serverID }) ?? ServerConfig()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SYSTEM PROMPT")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                Menu("Templates") {
                    ForEach(SystemPromptTemplate.all) { template in
                        Button(template.name) {
                            var updated = config
                            updated.systemPrompt = template.content
                            appVM.updateServer(updated)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .font(.caption)
                .fixedSize()
            }

            TextEditor(text: Binding(
                get: { config.systemPrompt },
                set: { newValue in
                    var updated = config
                    updated.systemPrompt = newValue
                    appVM.updateServer(updated)
                }
            ))
            .font(.body)
            .frame(minHeight: 100, maxHeight: 100)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
    }
}
