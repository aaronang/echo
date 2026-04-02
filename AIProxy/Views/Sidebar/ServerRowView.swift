import SwiftUI

struct ServerRowView: View {
    let config: ServerConfig
    @ObservedObject var processManager: ProcessManager
    let isRenaming: Bool
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var editText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            statusIcon

            if isRenaming {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .focused($isFocused)
                    .onSubmit {
                        let trimmed = editText.trimmingCharacters(in: .whitespaces)
                        onCommit(trimmed.isEmpty ? config.name : trimmed)
                    }
                    .onKeyPress(.escape) {
                        onCancel()
                        return .handled
                    }
                    .onAppear {
                        editText = config.name
                        isFocused = true
                    }
            } else {
                Text(config.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusIcon: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 11))
            .frame(width: 16, height: 18)
            .foregroundStyle(
                processManager.isRunning
                    ? Color(red: 38/255, green: 191/255, blue: 77/255)
                    : Color(red: 217/255, green: 217/255, blue: 217/255)
            )
    }
}
