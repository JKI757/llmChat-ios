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
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        List {
            ForEach(conversations, id: \.id) { conversation in
                VStack(alignment: .leading) {
                    // Display the conversation title as the main headline
                    Text(getConversationTitle(conversation))
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    // Display model and prompt information as secondary information
                    HStack {
                        Text("Model: \(conversation.model ?? "Unknown")")
                        
                        if conversation.userPrompt != nil {
                            Text("•")
                            Text("System + User Prompts")
                        } else {
                            Text("•")
                            Text("System Prompt")
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    
                    // Display date at the bottom
                    Text(conversation.timestamp?.formatted() ?? "Unknown date")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.vertical, 4)
                .onTapGesture {
                    onSelect(conversation)
                    // Dismiss this view to return to the chat view
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .onDelete(perform: deleteConversation)
        }
        .onAppear(perform: loadConversations)
        .onDisappear {
            // Force a refresh when view appears again
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                loadConversations()
            }
        }
        .navigationTitle("Conversation History")
    }

    private func loadConversations() {
        print("Loading conversations from Core Data")
        conversations = CoreDataManager.shared.fetchConversations()
        print("Loaded \(conversations.count) conversations")
    }

    private func deleteConversation(at offsets: IndexSet) {
        offsets.forEach { index in
            let conversation = conversations[index]
            // Also remove the title from UserDefaults when deleting a conversation
            if let id = conversation.id?.uuidString {
                UserDefaults.standard.removeObject(forKey: "conversation_title_\(id)")
            }
            CoreDataManager.shared.deleteConversation(conversation)
        }
        loadConversations()
    }
    
    // Helper function to get conversation title from UserDefaults or generate a default one
    private func getConversationTitle(_ conversation: Conversation) -> String {
        if let id = conversation.id?.uuidString,
           let title = UserDefaults.standard.string(forKey: "conversation_title_\(id)") {
            return title
        }
        
        // Fallback: Try to extract title from the first message
        if let messageData = conversation.messages,
           let messages = try? JSONDecoder().decode([ChatMessage].self, from: messageData),
           let firstUserMessage = messages.first(where: { $0.isUser })?.text {
            let truncatedTitle = String(firstUserMessage.prefix(50)) + (firstUserMessage.count > 50 ? "..." : "")
            return truncatedTitle
        }
        
        // Default title if nothing else works
        return "Conversation \(conversation.timestamp?.formatted(date: .abbreviated, time: .shortened) ?? "")" 
    }
}