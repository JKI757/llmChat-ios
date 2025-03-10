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
    @State private var scrollToBottom: Bool = false
    @State private var currentConversationID: UUID? = nil  // Track current conversation ID
    @State private var isContextSummarized: Bool = false  // Track if context is summarized
    @State private var contextUsagePercent: Double = 0  // Track context window usage
    let models = ["gpt-3.5-turbo", "gpt-4", "gpt-4-turbo"]
    let languages = ["English", "Spanish", "French", "German", "Chinese", "Japanese"]
    
    var body: some View {
        NavigationView {
            VStack {
                ScrollViewReader { scrollView in
                    List {
                        ForEach(messages) { message in
                            MessageRow(message: message)
                                .id(message.id) // Use message ID for scrolling
                        }
                        
                        // Show streaming message while it's in progress
                        if isStreaming {
                            Text("Streaming: \(streamingMessage)")
                                .padding()
                                .id("streamingMessage") // ID for scrolling to streaming content
                        }
                        
                        // Invisible spacer view at the bottom for scrolling
                        Color.clear.frame(height: 1).id("bottomID")
                    }
                    .onChange(of: messages.count) { _ in
                        // Scroll to bottom when messages change
                        withAnimation {
                            scrollView.scrollTo("bottomID", anchor: .bottom)
                        }
                    }
                    .onChange(of: streamingMessage) { _ in
                        // Scroll to bottom when streaming message updates
                        withAnimation {
                            scrollView.scrollTo("bottomID", anchor: .bottom)
                        }
                    }
                }
                inputArea
                
                // Context window usage indicator
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        // Model indicator
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.caption)
                            Text(storage.preferredModel)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                        
                        Spacer()
                        
                        Text("Context: \(Int(contextUsagePercent))%")
                            .font(.caption)
                    }
                    
                    // Progress bar for context window usage
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .frame(width: geometry.size.width, height: 4)
                                .opacity(0.3)
                                .foregroundColor(Color.gray)
                            
                            Rectangle()
                                .frame(width: min(CGFloat(contextUsagePercent) * geometry.size.width / 100, geometry.size.width), height: 4)
                                .foregroundColor(contextUsagePercent < 70 ? Color.green : (contextUsagePercent < 90 ? Color.yellow : Color.red))
                        }
                        .cornerRadius(2)
                    }
                    .frame(height: 4)
                    
                    if isContextSummarized {
                        Text("Context summarized to fit model limits")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
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
                    HStack(spacing: 16) {
                        // Clear conversation button
                        Button(action: clearConversation) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        
                        // New conversation button
                        Button(action: newConversation) {
                            Image(systemName: "square.and.pencil")
                        }
                        
                        // History button
                        NavigationLink(destination: ConversationHistoryView(onSelect: loadConversation)) {
                            Image(systemName: "clock")
                        }
                    }
                }
            }
        }
    }
    // Update the inputArea to make the stop button more visible
var inputArea: some View {
    HStack {
        TextField("Type a message...", text: $inputText, onCommit: {
            if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming {
                sendMessage()
            }
        })
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
    
    // Calculate context usage before sending
    updateContextUsage()
    
    // Sending message using LLMService with conversation history
    currentService = LLMService.sendStreamingMessage(
        message: messageSent,
        prompt: storage.prompt,
        model: storage.preferredModel,
        apiToken: storage.apiToken,
        endpoint: storage.apiEndpoint,
        preferredLanguage: selectedLanguage,
        useChatEndpoint: storage.useChatEndpoint,
        conversationHistory: messages, // Pass the full conversation history
        onUpdate: { [self] chunk, isFinal in
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
                    
                    // Save and update the current conversation ID if needed
                    let savedID = CoreDataManager.shared.saveConversation(
                        model: storage.preferredModel,
                        prompt: storage.prompt,
                        language: selectedLanguage,
                        messages: messages,
                        apiToken: storage.apiToken,
                        apiEndpoint: storage.apiEndpoint,
                        conversationID: currentConversationID
                    )
                    
                    // Update the conversation ID for future saves
                    if currentConversationID == nil {
                        currentConversationID = savedID
                    }
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
            let savedID = CoreDataManager.shared.saveConversation(
                model: storage.preferredModel,
                prompt: storage.prompt,
                language: selectedLanguage,
                messages: messages,
                apiToken: storage.apiToken,
                apiEndpoint: storage.apiEndpoint,
                conversationID: currentConversationID
            )
            
            // Update the conversation ID for future saves
            if currentConversationID == nil {
                currentConversationID = savedID
            }
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
            currentConversationID = conversation.id  // Set current conversation ID when loading
        }
    }
    
    // Clear the current conversation
    private func clearConversation() {
        messages = []
        streamingMessage = ""
        currentDelta = ""
        isStreaming = false
        currentConversationID = nil  // Reset conversation ID when clearing
        isContextSummarized = false
        contextUsagePercent = 0
        if let currentService = currentService {
            currentService.cancelStreaming()
        }
    }
    
    // Calculate and update context window usage indicators
    private func updateContextUsage() {
        // Get max tokens for the current model
        let maxTokens = LLMService.getMaxTokensForModel(storage.preferredModel)
        
        // Calculate total tokens in the conversation
        var totalTokens = LLMService.estimateTokens(in: storage.prompt) // System prompt
        
        for message in messages {
            totalTokens += LLMService.estimateTokens(in: message.text)
        }
        
        // Calculate percentage of context window used
        contextUsagePercent = min(Double(totalTokens) / Double(maxTokens) * 100, 100)
        
        // Check if we need to summarize (over 75% of context window)
        let tokenBuffer = min(1000, maxTokens / 4) // Reserve 25% or 1000 tokens, whichever is smaller
        isContextSummarized = totalTokens > maxTokens - tokenBuffer
        
        print("Context usage: \(Int(contextUsagePercent))% (\(totalTokens)/\(maxTokens) tokens)")
    }
    
    // Start a new conversation (clear and save current one if needed)
    private func newConversation() {
        // Save current conversation if it has content
        if !messages.isEmpty {
            CoreDataManager.shared.saveConversation(
                model: storage.preferredModel,
                prompt: storage.prompt,
                language: selectedLanguage,
                messages: messages,
                apiToken: storage.apiToken,
                apiEndpoint: storage.apiEndpoint,
                conversationID: currentConversationID
            )
        }
        
        // Reset the conversation ID for a truly new conversation
        currentConversationID = nil
        
        // Clear everything for a fresh start
        clearConversation()
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
