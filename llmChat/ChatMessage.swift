//
//  ChatMessage.swift
//  llmChat
//
//  Created by Joshua Impson on 3/7/25.
//

import Foundation

struct ChatMessage: Identifiable, Codable {
    var id = UUID()
    let text: String
    let isUser: Bool
}
