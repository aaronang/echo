import Foundation

enum Provider: String, Codable, CaseIterable, Identifiable {
    case claude
    case auggie
    case droid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .auggie: return "Auggie"
        case .droid: return "Droid"
        }
    }

    var badge: String {
        switch self {
        case .claude: return "ANT"
        case .auggie: return "AUG"
        case .droid: return "DRD"
        }
    }

    var badgeColor: String {
        switch self {
        case .claude: return "orange"
        case .auggie: return "blue"
        case .droid: return "green"
        }
    }
}

struct ServerConfig: Codable, Identifiable {
    var id: UUID
    var name: String
    var port: Int
    var provider: Provider
    var requestLogging: Bool
    var streamPassthrough: Bool
    var autoStart: Bool

    init(
        id: UUID = UUID(),
        name: String = "New Server",
        port: Int = 3000,
        provider: Provider = .claude,
        requestLogging: Bool = true,
        streamPassthrough: Bool = true,
        autoStart: Bool = false
    ) {
        self.id = id
        self.name = name
        self.port = port
        self.provider = provider
        self.requestLogging = requestLogging
        self.streamPassthrough = streamPassthrough
        self.autoStart = autoStart
    }
}
