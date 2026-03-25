import Foundation

@MainActor
class ProcessManager: ObservableObject {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    @Published var isRunning = false
    @Published var logs: [LogEntry] = []
    @Published var requestCount = 0
    @Published var errorCount = 0
    @Published var totalLatencyMs: Double = 0
    @Published var startTime: Date?

    var averageLatency: Double {
        guard requestCount > 0 else { return 0 }
        return totalLatencyMs / Double(requestCount)
    }

    var uptime: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    func start(aiProxyPath: String, provider: Provider, port: Int) {
        guard !isRunning else { return }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "\(aiProxyPath)/index.mjs", provider.rawValue]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["PORT": String(port)],
            uniquingKeysWith: { _, new in new }
        )
        process.currentDirectoryURL = URL(fileURLWithPath: aiProxyPath)
        process.standardOutput = stdout
        process.standardError = stderr

        self.process = process
        self.stdoutPipe = stdout
        self.stderrPipe = stderr

        readPipe(stdout, isStderr: false)
        readPipe(stderr, isStderr: true)

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.isRunning = false
                self?.startTime = nil
            }
        }

        do {
            try process.run()
            isRunning = true
            startTime = Date()
            requestCount = 0
            errorCount = 0
            totalLatencyMs = 0
            logs = []
        } catch {
            appendLog(LogEntry(
                timestamp: Date(),
                method: "ERR",
                path: "Failed to start: \(error.localizedDescription)",
                info: "",
                statusCode: nil,
                latency: nil,
                isError: true,
                rawLine: error.localizedDescription
            ))
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        isRunning = false
    }

    func clearLogs() {
        logs = []
    }

    private func readPipe(_ pipe: Pipe, isStderr: Bool) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }

            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                let entryLine: String
                if isStderr {
                    entryLine = "[stderr] \(trimmed)"
                } else {
                    entryLine = trimmed
                }

                if let entry = LogParser.parse(entryLine) {
                    Task { @MainActor [weak self] in
                        self?.appendLog(entry)
                    }
                }
            }
        }
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
