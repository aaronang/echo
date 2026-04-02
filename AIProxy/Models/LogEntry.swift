import Foundation

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let method: String
    let path: String
    let info: String
    let statusCode: Int?
    let latency: String?
    let isError: Bool
    let rawLine: String
    let requestBody: String?

    init(
        timestamp: Date,
        method: String,
        path: String,
        info: String,
        statusCode: Int?,
        latency: String?,
        isError: Bool,
        rawLine: String,
        requestBody: String? = nil
    ) {
        self.timestamp = timestamp
        self.method = method
        self.path = path
        self.info = info
        self.statusCode = statusCode
        self.latency = latency
        self.isError = isError
        self.rawLine = rawLine
        self.requestBody = requestBody
    }

    var is2xx: Bool {
        guard let code = statusCode else { return false }
        return (200..<300).contains(code)
    }

    var isErrorStatus: Bool {
        guard let code = statusCode else { return isError }
        return code >= 400
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return formatter.string(from: timestamp)
    }
}
