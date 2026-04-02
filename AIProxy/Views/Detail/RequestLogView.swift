import SwiftUI

struct RequestLogView: View {
    @ObservedObject var processManager: ProcessManager

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(processManager.logs) { entry in
                        TerminalEntryView(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .textSelection(.enabled)
            .onChange(of: processManager.logs.count) {
                if let last = processManager.logs.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .background {
            Group {
                Button("") {
                    processManager.clearLogs()
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("") {
                    guard let body = processManager.logs.last?.requestBody else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(body, forType: .string)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
    }
}

struct TerminalEntryView: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.formattedTime)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(nsColor: NSColor(red: 0.447, green: 0.447, blue: 0.447, alpha: 1)))
            Text(entry.rawLine.isEmpty ? entry.path : entry.rawLine)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(entry.isError ? Color.red : Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)))
        }
    }
}
