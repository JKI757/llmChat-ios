import Foundation

struct ChatMessage: Identifiable, Equatable, Codable {
    let content: String
    let role: String
    let timestamp: Date
    let isError: Bool
    
    var id: String { content + role + timestamp.description }
    var isUser: Bool { role == "user" }
    
    init(content: String, role: String = "user", timestamp: Date = Date(), isError: Bool = false) {
        self.content = content
        self.role = role
        self.timestamp = timestamp
        self.isError = isError
    }
    
    init(from message: Message) {
        self.content = message.content
        self.role = message.role
        self.timestamp = message.timestamp
        self.isError = message.isError
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case content, role, timestamp, isError
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decode(String.self, forKey: .content)
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "user"
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
    }
    
    // MARK: - Equatable
    
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}
