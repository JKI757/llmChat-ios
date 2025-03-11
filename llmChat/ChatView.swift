import CoreData
import SwiftUI
import MarkdownUI
import PhotosUI

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
    // Use EnvironmentObject instead of StateObject to ensure we're using the same instance
    // across the app and picking up changes from settings
    @EnvironmentObject var storage: AppStorageManager
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var selectedLanguage: String = "English"
    @State private var isStreaming: Bool = false
    @State private var streamingMessage: String = ""
    @State private var currentDelta: String = ""
    @State private var currentService: LLMService?  // Add state for current service
    @State private var scrollToBottom: Bool = false
    @State private var currentConversationID: UUID? = nil  // Track current conversation ID
    @State private var isContextSummarized: Bool = false  // Track if context is summarized
    @State private var contextUsagePercent: Double = 0  // Track context window usage
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    let models = ["gpt-3.5-turbo", "gpt-4", "gpt-4-turbo"]
    let languages = ["English", "Spanish", "French", "German", "Chinese", "Japanese", "Tagalog"]
    
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
    VStack(spacing: 8) {
        // Model and language selection row
        HStack {
            // Model indicator and picker
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
            
            // Temperature indicator
            HStack(spacing: 4) {
                Image(systemName: "thermometer")
                    .font(.caption)
                Text("\(storage.temperature, specifier: "%.1f")")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            
            Spacer()
            
            // Language picker
            Picker("Language", selection: $selectedLanguage) {
                ForEach(languages, id: \.self) { language in
                    Text(language)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .disabled(isStreaming)
        }
        .padding(.horizontal)
        
        // Input field, image picker and send button
        HStack {
            // Image picker button
            PhotosPicker(
                selection: $selectedItem,
                matching: .images,
                photoLibrary: .shared()) {
                    Image(systemName: "photo")
                        .foregroundColor(.blue)
                        .padding(8)
                }
                .disabled(isStreaming)
                .onChange(of: selectedItem) { newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                            selectedImageData = data
                            // Send the image message immediately
                            sendImageMessage(imageData: data)
                        }
                    }
                }
            
            TextField("Type a message...", text: $inputText, onCommit: {
                if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming {
                    sendMessage()
                }
            })
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .disabled(isStreaming)
            
            if isStreaming {
                Button(action: stopStreaming) {
                    Image(systemName: "stop.fill")
                        .foregroundColor(.red)
                        .padding(8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.gray.opacity(0.2))
            } else {
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .padding(8)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal)
    }
    .padding(.vertical, 8)
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
    
    // Reset selected image
    selectedItem = nil
    selectedImageData = nil
    
    
    // Add a timeout to handle connection failures
    // Using a longer timeout (30 seconds) to accommodate model loading time
    let timeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { _ in
        if isStreaming && streamingMessage.isEmpty {
            messages.append(ChatMessage(text: "Connection failed or timed out. The model might be taking longer to load or there might be an issue with the connection. Please try again.", isUser: false))
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
        temperature: storage.temperature, // Pass the temperature setting
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
            storage.preferredModel = conversation.model ?? "gpt-4"
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
            switch message.content {
            case .text(let text):
                totalTokens += LLMService.estimateTokens(in: text)
            case .image(_):
                // Estimate image tokens - this is a rough approximation
                // Most vision models count an image as ~1000 tokens
                totalTokens += 1000
            }
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
    
    // Send an image message
    private func sendImageMessage(imageData: Data) {
        // Only proceed if not currently streaming
        guard !isStreaming else { return }
        
        // Create and add the image message
        let imageMessage = ChatMessage(imageData: imageData, isUser: true)
        messages.append(imageMessage)
        
        // Reset any selected image data
        selectedItem = nil
        selectedImageData = nil
        
        // Calculate context usage
        updateContextUsage()
        
        // Optionally, you could automatically send a message to the LLM here
        // asking it to describe the image, but that would require vision capabilities
        // in the model, which may not be available in all endpoints
    }
}

// Extracted view for an individual chat message.
struct MessageRow: View {
    var message: ChatMessage
    @State private var showCopyConfirmation: Bool = false
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
                
                // User message content
                if case .text(let text) = message.content {
                    Text(text)
                        .padding()
                        .background(Color.blue.opacity(0.7))
                        .cornerRadius(10)
                        .foregroundColor(.white)
                        .contextMenu {
                            Button(action: {
                                UIPasteboard.general.string = text
                                showCopyConfirmation = true
                            }) {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                } else if case .image(let imageData) = message.content, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .cornerRadius(10)
                }
            } else {
                VStack(alignment: .leading) {
                    if case .text(let text) = message.content {
                        Markdown(text)
                            .markdownCodeSyntaxHighlighter(DefaultCodeSyntaxHighlighter())
                            .padding()
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(10)
                            .contextMenu {
                                Button(action: {
                                    UIPasteboard.general.string = text
                                    showCopyConfirmation = true
                                }) {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                            }
                    } else if case .image(let imageData) = message.content, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 200, maxHeight: 200)
                            .cornerRadius(10)
                    }
                    
                    if showCopyConfirmation {
                        Text("Copied to clipboard")
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.leading, 8)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showCopyConfirmation = false
                                }
                            }
                    }
                }
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
