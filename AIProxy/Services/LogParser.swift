import Foundation

struct LogParser {
    // Parses lines like: [log] POST / 200 1204ms
    // Also parses startup lines: ai-proxy [claude] running on http://localhost:3001
    static func parse(_ line: String) -> LogEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let entry = parseStructuredLog(trimmed) {
            return entry
        }

        return parseGenericLine(trimmed)
    }

    private static func parseStructuredLog(_ line: String) -> LogEntry? {
        // Match: [log] METHOD /path STATUS LATENCYms
        let pattern = #"^\[log\]\s+(\w+)\s+(\S+)\s+(\d+)\s+(\d+)ms$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 5 else { return nil }

        let method = String(line[Range(match.range(at: 1), in: line)!])
        let path = String(line[Range(match.range(at: 2), in: line)!])
        let status = Int(String(line[Range(match.range(at: 3), in: line)!]))
        let latencyMs = String(line[Range(match.range(at: 4), in: line)!])

        return LogEntry(
            timestamp: Date(),
            method: method,
            path: path,
            info: "",
            statusCode: status,
            latency: "\(latencyMs)ms",
            isError: (status ?? 0) >= 400,
            rawLine: line
        )
    }

    private static func parseGenericLine(_ line: String) -> LogEntry? {
        // Startup line
        if line.contains("running on") {
            return LogEntry(
                timestamp: Date(),
                method: "--",
                path: line,
                info: "",
                statusCode: nil,
                latency: nil,
                isError: false,
                rawLine: line
            )
        }

        // Error lines from stderr
        if line.hasPrefix("[") && line.contains("stderr") {
            return LogEntry(
                timestamp: Date(),
                method: "ERR",
                path: line,
                info: "",
                statusCode: nil,
                latency: nil,
                isError: true,
                rawLine: line
            )
        }

        // [request] lines
        if line.hasPrefix("[request]") {
            return LogEntry(
                timestamp: Date(),
                method: "POST",
                path: "/",
                info: String(line.dropFirst("[request]".count)).trimmingCharacters(in: .whitespaces),
                statusCode: nil,
                latency: nil,
                isError: false,
                rawLine: line
            )
        }

        return nil
    }
}
