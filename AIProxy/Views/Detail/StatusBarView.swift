import SwiftUI

struct StatusBarView: View {
    @ObservedObject var processManager: ProcessManager
    @State private var currentTime = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 20) {
            statItem("Requests", value: "\(processManager.requestCount)")
            statItem("Errors", value: "\(processManager.errorCount)", color: processManager.errorCount > 0 ? .red : nil)

            Divider()
                .frame(height: 14)

            statItem("Avg latency", value: processManager.requestCount > 0 ?
                     String(format: "%.0fms", processManager.averageLatency) : "--")

            Spacer()

            if processManager.isRunning {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("uptime \(formattedUptime)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }

    private func statItem(_ label: String, value: String, color: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color ?? .primary)
        }
    }

    private var formattedUptime: String {
        guard let start = processManager.startTime else { return "0s" }
        let interval = currentTime.timeIntervalSince(start)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(Int(interval))s"
        }
    }
}
