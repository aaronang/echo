import Foundation
import Darwin

@MainActor
class ProcessManager: ObservableObject {
    @Published var isRunning = false
    @Published var actualPort: Int = 0
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

    func start(port: Int, provider: Provider, systemPrompt: String, silent: Bool = false) {
        guard !isRunning else { return }

        if !silent { logInfo("Starting server…") }
        let port = availablePort(startingAt: port)
        let server = ProxyServer(port: port, provider: provider, systemPrompt: systemPrompt)
        server.onLog = { [weak self] entry in
            Task { @MainActor [weak self] in
                self?.appendLog(entry)
            }
        }
        server.onUnexpectedClose = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                let old = self.server
                self.server = nil
                self.isRunning = false
                self.actualPort = 0
                self.startTime = nil
                self.logWarning("Server closed unexpectedly, restarting…")
                await old?.stop()
                self.start(port: port, provider: provider, systemPrompt: systemPrompt, silent: true)
            }
        }
        self.server = server

        Task {
            do {
                try await server.start()
                // Guard against stop()/restart() having run during the async bind.
                guard self.server === server else { return }
                self.isRunning = true
                self.actualPort = port
                self.startTime = Date()
                self.requestCount = 0
                self.errorCount = 0
                self.totalLatencyMs = 0
                self.appendLog(LogEntry(
                    timestamp: Date(),
                    method: "SYS",
                    path: "Listening on http://localhost:\(port)",
                    info: "",
                    statusCode: nil,
                    latency: nil,
                    isError: false,
                    rawLine: "Listening on http://localhost:\(port). You can tell your agent to send a GET /help request to understand how to use this server."
                ))
            } catch {
                guard self.server === server else { return }
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
        logInfo("Server stopped")
        let s = server
        server = nil
        isRunning = false
        actualPort = 0
        startTime = nil
        Task { await s?.stop() }
    }

    func restart(port: Int, provider: Provider, systemPrompt: String) {
        logInfo("Restarting server…")
        let s = server
        server = nil
        isRunning = false
        actualPort = 0
        startTime = nil
        Task {
            await s?.stop()
            self.start(port: port, provider: provider, systemPrompt: systemPrompt, silent: true)
        }
    }

    func clearLogs() {
        logs = []
    }

    func logInfo(_ message: String) {
        appendLog(LogEntry(
            timestamp: Date(),
            method: "INFO",
            path: "",
            info: "",
            statusCode: nil,
            latency: nil,
            isError: false,
            rawLine: message
        ))
    }

    func logWarning(_ message: String) {
        appendLog(LogEntry(
            timestamp: Date(),
            method: "WARN",
            path: "",
            info: "",
            statusCode: nil,
            latency: nil,
            isError: false,
            rawLine: "⚠ \(message)"
        ))
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

    private func availablePort(startingAt preferred: Int) -> Int {
        for port in preferred...65000 where isPortFree(port) { return port }
        return preferred
    }

    private func isPortFree(_ port: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { Darwin.close(sock) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16HostToBig(UInt16(port))
        addr.sin_addr.s_addr = INADDR_ANY
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}
