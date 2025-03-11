//
//  ChatMessage.swift
//  llmChat
//
//  Created by Joshua Impson on 3/7/25.
//

import Foundation
import SwiftUI

enum MessageContent: Codable, Equatable {
    case text(String)
    case image(Data)
    
    enum CodingKeys: String, CodingKey {
        case type
        case textContent
        case imageData
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .textContent)
            self = .text(text)
        case "image":
            let data = try container.decode(Data.self, forKey: .imageData)
            self = .image(data)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown message type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .textContent)
        case .image(let data):
            try container.encode("image", forKey: .type)
            try container.encode(data, forKey: .imageData)
        }
    }
}

struct ChatMessage: Identifiable, Codable {
    var id = UUID()
    let content: MessageContent
    let isUser: Bool
    
    // For backward compatibility and convenience
    var text: String {
        if case .text(let string) = content {
            return string
        }
        return "[Image]"
    }
    
    // Convenience initializers
    init(text: String, isUser: Bool) {
        self.content = .text(text)
        self.isUser = isUser
    }
    
    init(imageData: Data, isUser: Bool) {
        self.content = .image(imageData)
        self.isUser = isUser
    }
}
