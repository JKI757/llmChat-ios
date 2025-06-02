import SwiftUI
import CoreData
import MarkdownUI

struct ConversationHistoryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var appStorage: AppStorageManager
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Conversation.timestamp, ascending: false)],
        animation: .default)
    private var conversations: FetchedResults<Conversation>
    
    var body: some View {
        NavigationView {
            List {
                ForEach(conversations, id: \.objectID) { conversation in
                    NavigationLink(destination: ConversationDetailView(conversation: conversation)
                        .environmentObject(appStorage)) {
                        ConversationRowView(conversation: conversation)
                            .environmentObject(appStorage)
                    }
                }
                .onDelete(perform: deleteConversations)
            }
            .navigationTitle("Conversation History")
        }
    }
    
    private func deleteConversations(offsets: IndexSet) {
        withAnimation {
            offsets.map { conversations[$0] }.forEach(viewContext.delete)
            
            do {
                try viewContext.save()
            } catch {
                print("Error deleting conversations: \(error)")
            }
        }
    }
}

struct ConversationRowView: View {
    let conversation: Conversation
    @EnvironmentObject private var appStorage: AppStorageManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(conversation.title ?? "Untitled Conversation")
                .font(.headline)
                .lineLimit(1)
            
            HStack {
                Text(conversation.model ?? "Unknown Model")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                Text(conversation.timestamp?.formatted() ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let endpointID = conversation.endpointID,
               let endpoint = appStorage.savedEndpoints.first(where: { $0.id == endpointID }) {
                Text("Endpoint: \(endpoint.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct ConversationDetailView: View {
    let conversation: Conversation
    @State private var messages: [ChatMessage] = []
    @EnvironmentObject private var appStorage: AppStorageManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Conversation metadata section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Model: \(conversation.model ?? "Unknown")")
                            .font(.headline)
                        
                        Spacer()
                        
                        Text(conversation.timestamp?.formatted() ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let language = conversation.language {
                        Text("Language: \(language)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let endpointID = conversation.endpointID,
                       let endpoint = appStorage.savedEndpoints.first(where: { $0.id == endpointID }) {
                        Text("Endpoint: \(endpoint.name)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 8)
                .padding(.horizontal, 8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                // Prompts section
                if let systemPrompt = conversation.systemPrompt, !systemPrompt.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Prompt")
                            .font(.headline)
                        
                        Text(systemPrompt)
                            .padding(8)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .padding(.vertical, 4)
                }
                
                if let userPrompt = conversation.userPrompt, !userPrompt.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("User Prompt")
                            .font(.headline)
                        
                        Text(userPrompt)
                            .padding(8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .padding(.vertical, 4)
                }
                
                Divider()
                    .padding(.vertical, 8)
                
                // Messages section
                Text("Messages")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                ForEach(messages) { message in
                    MessageView(message: message)
                        .padding(.vertical, 2)
                }
            }
            .padding()
        }
        .navigationTitle(conversation.title ?? "Conversation Details")
        .onAppear {
            loadMessages()
        }
    }
    
    private func loadMessages() {
        messages = CoreDataManager.shared.getMessages(for: conversation)
    }
}

struct MessageView: View {
    let message: ChatMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.isUser ? "User" : "Assistant")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(message.isUser ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                    .cornerRadius(12)
                
                Spacer()
                
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if message.isError {
                Text(message.content.textValue)
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
            } else {
                switch message.content {
                case .text(let textContent):
                    Markdown(textContent)
                        .padding(8)
                        .background(message.isUser ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(message.isUser ? Color.blue.opacity(0.3) : Color.gray.opacity(0.3), lineWidth: 1)
                        )
                case .image(let base64Image):
                    if let imageData = Data(base64Encoded: base64Image),
                       let uiImage = UIImage(data: imageData) {
                        VStack(alignment: .center) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 240, maxHeight: 240)
                                .cornerRadius(8)
                                .padding(8)
                                .background(message.isUser ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(message.isUser ? Color.blue.opacity(0.3) : Color.gray.opacity(0.3), lineWidth: 1)
                                )
                            
                            Text("[Image]")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("[Unable to load image]")
                            .foregroundColor(.red)
                            .padding(8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            }
        }
    }
}

struct ConversationHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ConversationHistoryView()
                .environment(\.managedObjectContext, CoreDataManager.shared.container.viewContext)
                .environmentObject(AppStorageManager.shared)
        }
    }
}
