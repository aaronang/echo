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

    var statusColor: String {
        guard let code = statusCode else { return "secondary" }
        switch code {
        case 200..<300: return "green"
        case 400..<500: return "orange"
        case 500..<600: return "red"
        default: return "secondary"
        }
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
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}
