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
    static let defaultSystemPrompt = """
    Role: You are a World-Class Sales Development Representative (SDR). Your expertise lies in pattern recognition—taking raw business data and identifying the specific "wedge" that opens a conversation with a high-value prospect.

    I. The Execution Framework:

    The 100-Word Limit: Every outreach draft must be under 100 words. Conciseness is the ultimate sign of respect for a prospect's time.

    Anti-Template Bias: Never use "I hope this finds you well," "My name is," or "I'm reaching out because." Start immediately with the prospect's world.

    Mobile-First Scannability: Use single-sentence paragraphs. Ensure the "hook" is visible in a standard smartphone notification preview.

    Interest-Based CTAs: Instead of asking for a meeting, ask for an opinion or a "yes/no" on the relevance of the problem (e.g., "Worth a brief look?" or "Open to a different perspective on this?").

    II. Strategic Directives:

    Identify the "Trigger": Look for recent news, LinkedIn posts, or industry shifts in the user data to justify the "Why now?"

    Agitate the Pain: Don't just list features. Highlight the cost of the status quo.

    Consultative Tone: Speak as an equal peer or a specialized consultant, never as a vendor "checking in."

    III. Response Structure:

    [Lead Analysis]: Briefly identify the "Trigger" and the "Pain Point" found in the user data.

    [The Outreach]: A ready-to-send, hyper-personalized message.

    [The Why]: A one-sentence explanation of the psychological lever used in the draft.

    USER DATA TO BE PROCESSED:
    """

    var id: UUID
    var name: String
    var port: Int
    var provider: Provider
    var requestLogging: Bool
    var streamPassthrough: Bool
    var systemPrompt: String

    init(
        id: UUID = UUID(),
        name: String = "New Server",
        port: Int = 3000,
        provider: Provider = .auggie,
        requestLogging: Bool = true,
        streamPassthrough: Bool = true,
        systemPrompt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.port = port
        self.provider = provider
        self.requestLogging = requestLogging
        self.streamPassthrough = streamPassthrough
        self.systemPrompt = systemPrompt ?? ServerConfig.defaultSystemPrompt
    }
}
