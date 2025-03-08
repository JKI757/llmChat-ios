import CoreData
import SwiftUI
import MarkdownUI

// Add structures for handling streaming response
struct StreamResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    
    struct Choice: Codable {
        let index: Int
        struct Delta: Codable {
            let role: String?
            let content: String?
        }
        let delta: Delta
        let logprobs: String?
        let finish_reason: String?
    }
}

struct ChatView: View {
    @StateObject private var storage = AppStorageManager()
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var selectedModel: String = "gpt-4"
    @State private var selectedConversation: Conversation?
    @State private var selectedLanguage: String = "English"
    @State private var isStreaming: Bool = false
    @State private var streamingMessage: String = ""
    @State private var currentDelta: String = ""
    @State private var currentService: LLMService?  // Add state for current service
    let models = ["gpt-3.5-turbo", "gpt-4", "gpt-4-turbo"]
    let languages = ["English", "Spanish", "French", "German", "Chinese", "Japanese"]
    
    var body: some View {
        NavigationView {
            VStack {
                List {
                    ForEach(messages) { message in
                        MessageRow(message: message)
                    }
                    
                    // Show streaming message while it's in progress
                    if isStreaming {
                        Text("Streaming: \(streamingMessage)")
                            .padding()
                    }
                }
                inputArea
                
                // Debug info view
                VStack(alignment: .leading) {
                    Text("Debug Info:")
                        .font(.caption)
                    Text("isStreaming: \(isStreaming ? "true" : "false")")
                        .font(.caption)
                    Text("streamingMessage length: \(streamingMessage.count)")
                        .font(.caption)
                    Text("currentDelta length: \(currentDelta.count)")
                        .font(.caption)
                    Text("messages count: \(messages.count)")
                        .font(.caption)
                }
                .padding()
                .background(Color(.systemGray6))
            }
            .navigationTitle("Chat")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: ConversationHistoryView(onSelect: loadConversation)) {
                        Image(systemName: "clock")
                    }
                }
            }
        }
    }
    // Update the inputArea to make the stop button more visible
var inputArea: some View {
    HStack {
        TextField("Type a message...", text: $inputText)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .disabled(isStreaming)
        
        Picker("Language", selection: $selectedLanguage) {
            ForEach(languages, id: \.self) { language in
                Text(language)
            }
        }
        .pickerStyle(MenuPickerStyle())
        .disabled(isStreaming)
        
        if isStreaming {
            Button(action: stopStreaming) {
                Image(systemName: "stop.fill")
                    .foregroundColor(.red)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.gray.opacity(0.2))
        } else {
            Button(action: sendMessage) {
                Image(systemName: "paperplane.fill")
                    .padding()
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    .padding()
}


// Update sendMessage function to handle streaming properly
private func sendMessage() {
    isStreaming = true
    
    
    // Append user message
    let userMessage = ChatMessage(text: inputText, isUser: true)
    messages.append(userMessage)
    let messageSent = inputText
    
    inputText = ""
    streamingMessage = ""
    currentDelta = ""
    
    
    // Add a timeout to handle connection failures
    let timeoutTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
        if isStreaming && streamingMessage.isEmpty {
            messages.append(ChatMessage(text: "Connection failed or timed out. Please try again.", isUser: false))
            isStreaming = false
        }
    }
    
    // Sending message using LLMService
    currentService = LLMService.sendStreamingMessage(
        message: messageSent,
        prompt: storage.prompt,
        model: storage.preferredModel,
        apiToken: storage.apiToken,
        endpoint: storage.apiEndpoint,
        preferredLanguage: selectedLanguage,
        useChatEndpoint: storage.useChatEndpoint,
        onUpdate: { chunk, isFinal in
            print("Raw chunk: \(chunk)")
            
            DispatchQueue.main.async {
                // Cancel the timeout timer once we get any response
                timeoutTimer.invalidate()
                
                guard isStreaming else { return }
                
                if isFinal {
                    print("Final chunk received")  // Debug print
                    if !currentDelta.isEmpty {
                        print("Adding final message with length: \(currentDelta.count)")  // Debug print
                        messages.append(ChatMessage(text: currentDelta, isUser: false))
                    }
                    isStreaming = false
                    streamingMessage = ""
                    currentDelta = ""
                    
                    CoreDataManager.shared.saveConversation(
                        model: storage.preferredModel,
                        prompt: storage.prompt,
                        language: selectedLanguage,
                        messages: messages
                    )
                } else {
                    // Strip "data: " prefix and parse JSON
                    if chunk.hasPrefix("data: ") {
                        let jsonString = String(chunk.dropFirst(6))
                        if let data = jsonString.data(using: .utf8),
                           let response = try? JSONDecoder().decode(StreamResponse.self, from: data) {
                            if let content = response.choices.first?.delta.content {
                                currentDelta += content
                                streamingMessage = currentDelta
                                print("Added content: \(content)")
                            }
                        } else {
                            print("Failed to parse JSON: \(jsonString)")
                        }
                    }
                }
            }
        }
    )
}
    private func stopStreaming() {
        currentService?.cancelStreaming()  // Cancel the request
        isStreaming = false
        
        // If there was content in the current delta, save it
        if !currentDelta.isEmpty {
            messages.append(ChatMessage(text: currentDelta + "\n\n[Response interrupted]", isUser: false))
            
            // Save the conversation even if interrupted
            CoreDataManager.shared.saveConversation(
                model: storage.preferredModel,
                prompt: storage.prompt,
                language: selectedLanguage,
                messages: messages
            )
        }
        
        streamingMessage = ""
        currentDelta = ""
        currentService = nil
    }
    // Moved helper function inside the struct.
    private func loadConversation(_ conversation: Conversation) {
        if let data = conversation.messages,
           let savedMessages = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            messages = savedMessages
            selectedModel = conversation.model ?? "gpt-4"
            storage.prompt = conversation.prompt ?? "You are a helpful assistant."
            selectedLanguage = conversation.language ?? "English"
        }
    }
}

// Extracted view for an individual chat message.
struct MessageRow: View {
    var message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
                Text(message.text)
                    .padding()
                    .background(Color.blue.opacity(0.7))
                    .cornerRadius(10)
                    .foregroundColor(.white)
            } else {
                Markdown(message.text)
                    .markdownCodeSyntaxHighlighter(DefaultCodeSyntaxHighlighter())
                    .padding()
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(10)
            }
        }
    }
}

struct DefaultCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    func highlightCode(_ code: String, language: String?) -> Text {
        return highlight(code)
    }
    
    func highlight(_ code: String) -> Text {
        // A simple highlighter that returns the code as plain text
        Text(code)
    }
}
