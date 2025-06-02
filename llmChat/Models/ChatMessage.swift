import Foundation
import SwiftUI

enum MessageContent: Equatable, Codable {
    case text(String)
    case image(String) // Base64 encoded image
    
    var textValue: String {
        switch self {
        case .text(let text): return text
        case .image: return "[Image]"
        }
    }
    
    // For encoding/decoding
    private enum ContentType: String, Codable {
        case text, image
    }
    
    private enum CodingKeys: String, CodingKey {
        case type, value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ContentType.self, forKey: .type)
        
        switch type {
        case .text:
            let value = try container.decode(String.self, forKey: .value)
            self = .text(value)
        case .image:
            let value = try container.decode(String.self, forKey: .value)
            self = .image(value)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .text(let value):
            try container.encode(ContentType.text, forKey: .type)
            try container.encode(value, forKey: .value)
        case .image(let value):
            try container.encode(ContentType.image, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

struct ChatMessage: Identifiable, Equatable, Codable {
    let content: MessageContent
    let role: String
    let timestamp: Date
    let isError: Bool
    
    var id: String { 
        let contentString: String
        switch content {
        case .text(let text): contentString = text
        case .image(let base64): contentString = base64.prefix(20).description
        }
        return contentString + role + timestamp.description 
    }
    var isUser: Bool { role == "user" }
    
    init(content: String, role: String = "user", timestamp: Date = Date(), isError: Bool = false) {
        self.content = .text(content)
        self.role = role
        self.timestamp = timestamp
        self.isError = isError
    }
    
    init(imageContent: String, role: String = "user", timestamp: Date = Date(), isError: Bool = false) {
        self.content = .image(imageContent)
        self.role = role
        self.timestamp = timestamp
        self.isError = isError
    }
    
    init(from message: Message) {
        // For CoreData compatibility, assume all stored messages are text
        self.content = .text(message.content)
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
        
        // Handle both new and old format
        if let contentValue = try? container.decode(MessageContent.self, forKey: .content) {
            content = contentValue
        } else if let stringContent = try? container.decode(String.self, forKey: .content) {
            // Legacy format - convert string to MessageContent.text
            content = .text(stringContent)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .content, in: container, debugDescription: "Cannot decode content")
        }
        
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "user"
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
    }
    
    // MARK: - Equatable
    
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}
