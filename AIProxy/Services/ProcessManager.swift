import Foundation

@MainActor
class ProcessManager: ObservableObject {
    @Published var isRunning = false
    @Published var logs: [LogEntry] = []
    @Published var requestCount = 0
    @Published var errorCount = 0
    @Published var totalLatencyMs: Double = 0
    @Published var startTime: Date?

    private var server: ProxyServer?

    var averageLatency: Double {
        guard requestCount > 0 else { return 0 }
        return totalLatencyMs / Double(requestCount)
    }

    var uptime: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    func start(port: Int, provider: Provider, systemPrompt: String) {
        guard !isRunning else { return }

        let server = ProxyServer(port: port, provider: provider, systemPrompt: systemPrompt)
        server.onLog = { [weak self] entry in
            Task { @MainActor [weak self] in
                self?.appendLog(entry)
            }
        }
        self.server = server

        Task {
            do {
                try await server.start()
                self.isRunning = true
                self.startTime = Date()
                self.requestCount = 0
                self.errorCount = 0
                self.totalLatencyMs = 0
                self.logs = [LogEntry(
                    timestamp: Date(),
                    method: "SYS",
                    path: "Listening on http://localhost:\(port)",
                    info: "",
                    statusCode: nil,
                    latency: nil,
                    isError: false,
                    rawLine: "Listening on http://localhost:\(port)"
                )]
            } catch {
                self.appendLog(LogEntry(
                    timestamp: Date(),
                    method: "ERR",
                    path: "Failed to start: \(error.localizedDescription)",
                    info: "",
                    statusCode: nil,
                    latency: nil,
                    isError: true,
                    rawLine: error.localizedDescription
                ))
                self.server = nil
            }
        }
    }

    func stop() {
        server?.stop()
        server = nil
        isRunning = false
        startTime = nil
    }

    func restart(port: Int, provider: Provider, systemPrompt: String) {
        stop()
        start(port: port, provider: provider, systemPrompt: systemPrompt)
    }

    func clearLogs() {
        logs = []
    }

    private func appendLog(_ entry: LogEntry) {
        logs.append(entry)
        if entry.statusCode != nil {
            requestCount += 1
        }
        if entry.isErrorStatus {
            errorCount += 1
        }
        if let latency = entry.latency,
           let ms = Double(latency.replacingOccurrences(of: "ms", with: "")) {
            totalLatencyMs += ms
        }
    }
}
