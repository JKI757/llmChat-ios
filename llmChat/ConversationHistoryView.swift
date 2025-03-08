//
//  ConversationHistoryView.swift
//  llmChat
//
//  Created by Joshua Impson on 3/7/25.
//


import SwiftUI

struct ConversationHistoryView: View {
    let onSelect: (Conversation) -> Void
    @State private var conversations: [Conversation] = []

    var body: some View {
        List {
            ForEach(conversations, id: \.id) { conversation in
                VStack(alignment: .leading) {
                    Text("Model: \(conversation.model ?? "Unknown")")
                        .font(.headline)
                    Text("Prompt: \(conversation.prompt ?? "No prompt")")
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(conversation.timestamp?.formatted() ?? "Unknown date")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .onTapGesture {
                    onSelect(conversation)
                }
            }
            .onDelete(perform: deleteConversation)
        }
        .onAppear(perform: loadConversations)
        .navigationTitle("Conversation History")
    }

    private func loadConversations() {
        conversations = CoreDataManager.shared.fetchConversations()
    }

    private func deleteConversation(at offsets: IndexSet) {
        offsets.forEach { index in
            CoreDataManager.shared.deleteConversation(conversations[index])
        }
        loadConversations()
    }
}