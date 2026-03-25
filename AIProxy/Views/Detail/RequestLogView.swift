import SwiftUI

enum LogFilter: String, CaseIterable {
    case all = "All"
    case success = "2xx"
    case errors = "Errors"
}

struct RequestLogView: View {
    @ObservedObject var processManager: ProcessManager
    @State private var filter: LogFilter = .all

    private var filteredLogs: [LogEntry] {
        switch filter {
        case .all: return processManager.logs
        case .success: return processManager.logs.filter { $0.is2xx }
        case .errors: return processManager.logs.filter { $0.isErrorStatus }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack {
                Text("Request Log")
                    .font(.headline)

                Spacer()

                Picker("", selection: $filter) {
                    ForEach(LogFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Button("Clear") {
                    processManager.clearLogs()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Log table
            if filteredLogs.isEmpty {
                Spacer()
                Text("No log entries")
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    List(filteredLogs) { entry in
                        LogRowView(entry: entry)
                            .id(entry.id)
                            .listRowSeparator(.visible)
                    }
                    .listStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .onChange(of: processManager.logs.count) {
                        if let last = filteredLogs.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

struct LogRowView: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.formattedTime)
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .leading)

            Text(entry.method)
                .fontWeight(.semibold)
                .foregroundStyle(methodColor)
                .frame(width: 36, alignment: .leading)

            Text(entry.path)
                .lineLimit(1)
                .truncationMode(.middle)

            if !entry.info.isEmpty {
                Text(entry.info)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let code = entry.statusCode {
                Text("\(code)")
                    .fontWeight(.medium)
                    .foregroundStyle(statusColor)
                    .frame(width: 32, alignment: .trailing)
            }

            if let latency = entry.latency {
                Text(latency)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.vertical, 1)
    }

    private var methodColor: Color {
        switch entry.method {
        case "POST": return .blue
        case "GET": return .green
        case "ERR": return .red
        default: return .secondary
        }
    }

    private var statusColor: Color {
        guard let code = entry.statusCode else { return .secondary }
        switch code {
        case 200..<300: return .green
        case 400..<500: return .orange
        case 500..<600: return .red
        default: return .secondary
        }
    }
}
