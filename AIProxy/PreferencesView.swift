import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var appVM: AppViewModel

    var body: some View {
        Form {
            Section("ai-proxy Location") {
                HStack {
                    TextField("Path to ai-proxy directory", text: $appVM.aiProxyPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        panel.message = "Select the ai-proxy directory containing index.mjs"
                        if panel.runModal() == .OK, let url = panel.url {
                            appVM.aiProxyPath = url.path
                        }
                    }
                }

                if !appVM.aiProxyPath.isEmpty {
                    let exists = FileManager.default.fileExists(atPath: appVM.aiProxyPath + "/index.mjs")
                    Label(
                        exists ? "index.mjs found" : "index.mjs not found at this path",
                        systemImage: exists ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(exists ? .green : .red)
                    .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 150)
    }
}
