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
    let system_fingerprint: String?
    let service_tier: String?
    
    struct Choice: Codable {
        let index: Int
        struct Delta: Codable {
            let role: String?
            let content: String?
            
            // Empty initializer to handle empty delta objects
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                role = try container.decodeIfPresent(String.self, forKey: .role)
                content = try container.decodeIfPresent(String.self, forKey: .content)
            }
            
            private enum CodingKeys: String, CodingKey {
                case role, content
            }
        }
        let delta: Delta
        let logprobs: JSONValue?
        let finish_reason: String?
    }
}

// Helper type to handle null values in JSON
enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
            return
        }
        
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        
        if let value = try? container.decode(Int.self) {
            self = .int(value)
            return
        }
        
        if let value = try? container.decode(Double.self) {
            self = .double(value)
            return
        }
        
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        
        if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
            return
        }
        
        if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
            return
        }
        
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode JSONValue")
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
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
    @State private var isCheckingEndpoint: Bool = false  // Track if we're currently checking the endpoint
    // Use the centralized language list from AppStorageManager
    let languages = AppStorageManager.supportedLanguages
    
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
                // Text input field and send button
                HStack {
                    TextField("Type a message...", text: $inputText, onCommit: {
                        if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming {
                            sendMessage()
                            // Explicitly clear the input text when user presses Enter
                            DispatchQueue.main.async {
                                self.inputText = ""
                            }
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
                
                // Parameter selectors - now below the text entry and context display
                parameterSelectors
                
                // Add the hidden image picker
                hiddenImagePicker
            }
            .navigationTitle("Chat")
            .onAppear {
                // Check if we have a valid endpoint and fetch available models
                checkEndpoint()
            }
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
    // Parameter selectors view - now a separate component
var parameterSelectors: some View {
    VStack(spacing: 8) {
        // Double-stacked parameter selectors
        VStack(spacing: 8) {
            // Top row: Prompt and Model selectors
            HStack(spacing: 12) {
                // Prompt selector
                Menu {
                    ForEach(storage.savedPrompts) { prompt in
                        Button(action: {
                            storage.selectPrompt(id: prompt.id)
                        }) {
                            HStack {
                                Text(prompt.name)
                                if isCurrentPromptSelected(prompt) {
                                    Image(systemName: "checkmark")
                                }
                                if storage.defaultPromptID == prompt.id {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    NavigationLink(destination: PromptsView()) {
                        Label("Manage Prompts", systemImage: "gear")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "text.bubble")
                            .font(.caption)
                        Text(getCurrentPromptName())
                            .font(.caption)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(8)
                }
                .disabled(isStreaming)
                .frame(maxWidth: .infinity)
                
                // Model selector
                Menu {
                    if isCheckingEndpoint {
                        Text("Checking endpoint...")
                            .foregroundColor(.secondary)
                    } else if !storage.hasValidEndpoint {
                        Text("No valid endpoint")
                            .foregroundColor(.secondary)
                        
                        Divider()
                        
                        NavigationLink(destination: SettingsView()) {
                            Label("Configure Endpoint", systemImage: "gear")
                        }
                    } else if storage.availableModels.isEmpty {
                        Text("No models available")
                            .foregroundColor(.secondary)
                        
                        Divider()
                        
                        NavigationLink(destination: SettingsView()) {
                            Label("Configure Endpoint", systemImage: "gear")
                        }
                    } else {
                        // Show all available models from the endpoint
                        ForEach(storage.availableModels, id: \.self) { model in
                            Button(action: { storage.preferredModel = model }) {
                                HStack {
                                    Text(model)
                                    if storage.preferredModel == model {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.caption)
                        Text(storage.preferredModel)
                            .font(.caption)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .disabled(isStreaming)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            
            // Bottom row: Temperature and Language selectors
            HStack(spacing: 12) {
                // Temperature selector
                Menu {
                    Button(action: { storage.temperature = 0.0 }) {
                        HStack {
                            Text("0.0 - Precise")
                            if storage.temperature == 0.0 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Button(action: { storage.temperature = 0.3 }) {
                        HStack {
                            Text("0.3 - Balanced")
                            if storage.temperature == 0.3 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Button(action: { storage.temperature = 0.7 }) {
                        HStack {
                            Text("0.7 - Creative")
                            if storage.temperature == 0.7 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Button(action: { storage.temperature = 1.0 }) {
                        HStack {
                            Text("1.0 - Very Creative")
                            if storage.temperature == 1.0 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "thermometer")
                            .font(.caption)
                        Text("\(storage.temperature, specifier: "%.1f")")
                            .font(.caption)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                .disabled(isStreaming)
                .frame(maxWidth: .infinity)
                
                // Language picker
                Picker("Language", selection: $selectedLanguage) {
                    ForEach(languages, id: \.self) { language in
                        Text(language)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .disabled(isStreaming)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
        }
    }
    .padding(.vertical, 8)
    .background(Color(.systemGray6).opacity(0.5))
}

// Hidden image picker that can still be triggered programmatically but isn't visible in the UI
var hiddenImagePicker: some View {
    PhotosPicker(
        selection: $selectedItem,
        matching: .images,
        photoLibrary: .shared()) {
            EmptyView() // No visible UI element
        }
        .frame(width: 0, height: 0)
        .opacity(0)
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
}

// Update sendMessage function to handle streaming properly
private func sendMessage() {
    isStreaming = true
    
    // Append user message
    let userMessage = ChatMessage(text: inputText, isUser: true)
    messages.append(userMessage)
    let messageSent = inputText
    
    // Clear the input text field
    DispatchQueue.main.async {
        self.inputText = ""
    }
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
    
    // Debug the API token before sending
    print("API token in ChatView: \(storage.apiToken.isEmpty ? "EMPTY" : "\(storage.apiToken.prefix(min(5, storage.apiToken.count)))...")")
    
    // Sending message using LLMService with conversation history
    currentService = LLMService.sendStreamingMessage(
        message: messageSent,
        systemPrompt: storage.systemPrompt,
        userPrompt: storage.userPrompt,
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
                    } else {
                        print("No content accumulated to add as final message")
                        // If we didn't accumulate any content but received a final signal,
                        // add an empty message to avoid confusion
                        messages.append(ChatMessage(text: "[No response received from the model. Please try again or check your API settings.]", isUser: false))
                    }
                    isStreaming = false
                    streamingMessage = ""
                    currentDelta = ""
                    
                    // Save and update the current conversation ID if needed
                    do {
                        let savedID = try CoreDataManager.shared.saveConversation(
                            model: storage.preferredModel,
                            systemPrompt: storage.systemPrompt,
                            userPrompt: storage.userPrompt,
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
                    } catch {
                        print("Failed to save conversation: \(error)")
                    }
                    

                } else {
                    // Handle different response formats
                    if chunk.hasPrefix("data: ") {
                        // OpenAI-style format with "data: " prefix
                        let jsonString = String(chunk.dropFirst(6))
                        
                        // Handle [DONE] messages
                        if jsonString.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
                            print("Received [DONE] message")
                            // If we have accumulated content, add it as a final message
                            if !currentDelta.isEmpty {
                                print("Adding final message from [DONE] with content: \(currentDelta)")
                                messages.append(ChatMessage(text: currentDelta, isUser: false))
                                isStreaming = false
                            }
                            return
                        }
                        
                        // Try to parse the response using different approaches
                        if let data = jsonString.data(using: .utf8) {
                            // First try to parse as OpenAI format
                            if let response = try? JSONDecoder().decode(StreamResponse.self, from: data) {
                                print("Successfully decoded StreamResponse: \(response.id)")
                                
                                // Check if this is a completion message with empty delta
                                if let finishReason = response.choices.first?.finish_reason, 
                                   finishReason == "stop" {
                                    print("Received completion message with finish_reason: stop")
                                    
                                    // If we have content accumulated and this is the final message, add it
                                    if !currentDelta.isEmpty && isFinal {
                                        print("Adding final message with accumulated content: \(currentDelta)")
                                        messages.append(ChatMessage(text: currentDelta, isUser: false))
                                        isStreaming = false
                                    }
                                } 
                                // Check if there's content to add
                                else if let content = response.choices.first?.delta.content {
                                    currentDelta += content
                                    streamingMessage = currentDelta
                                    print("Added content: \(content)")
                                }
                                // If we got here, we successfully parsed but there was no content
                                else {
                                    print("Parsed response but no content in delta")
                                }
                            }
                            // If standard format fails, try generic JSON parsing
                            else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                print("Trying alternative JSON parsing")
                                
                                // Try to find content in various locations
                                if let choices = json["choices"] as? [[String: Any]],
                                   let firstChoice = choices.first {
                                    
                                    // Check for delta.content structure
                                    if let delta = firstChoice["delta"] as? [String: Any],
                                       let content = delta["content"] as? String {
                                        currentDelta += content
                                        streamingMessage = currentDelta
                                        print("Found content in delta.content: \(content)")
                                    }
                                    // Check for text structure
                                    else if let text = firstChoice["text"] as? String {
                                        currentDelta += text
                                        streamingMessage = currentDelta
                                        print("Found content in text: \(text)")
                                    }
                                    // Check for content structure
                                    else if let content = firstChoice["content"] as? String {
                                        currentDelta += content
                                        streamingMessage = currentDelta
                                        print("Found content in content: \(content)")
                                    }
                                    // Check for empty delta (completion message)
                                    else if let finishReason = firstChoice["finish_reason"] as? String, 
                                            finishReason == "stop" {
                                        print("Found completion message with finish_reason: stop")
                                    }
                                    else {
                                        print("No recognizable content format in choices")
                                    }
                                }
                                // Try to find direct content
                                else if let content = json["content"] as? String {
                                    currentDelta += content
                                    streamingMessage = currentDelta
                                    print("Found direct content: \(content)")
                                }
                                else if let text = json["text"] as? String {
                                    currentDelta += text
                                    streamingMessage = currentDelta
                                    print("Found direct text: \(text)")
                                }
                                else {
                                    print("No recognizable content in JSON")
                                }
                            }
                            else {
                                print("Failed to parse JSON: \(jsonString)")
                            }
                        }
                    } else {
                        // Handle plain text responses (no JSON)
                        // Some APIs return raw text without JSON formatting
                        let trimmedChunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedChunk.isEmpty {
                            currentDelta += trimmedChunk
                            streamingMessage = currentDelta
                            print("Added plain text: \(trimmedChunk)")
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
            do {
                let savedID = try CoreDataManager.shared.saveConversation(
                    model: storage.preferredModel,
                    systemPrompt: storage.systemPrompt,
                    userPrompt: storage.userPrompt,
                    language: selectedLanguage,
                    messages: messages,
                    apiToken: storage.apiToken,
                    apiEndpoint: storage.apiEndpoint
                )
                
                if let id = savedID {
                    currentConversationID = id
                }
            } catch {
                print("Failed to save interrupted conversation: \(error)")
            }
        }
        
        // Reset streaming state
        streamingMessage = ""
        currentDelta = ""
    }
    
    private func checkEndpoint() {
        // Don't check if we're already checking
        guard !isCheckingEndpoint else { return }
        
        // Don't check if there's no endpoint configured
        guard !storage.apiEndpoint.isEmpty else {
            storage.hasValidEndpoint = false
            storage.availableModels = []
            return
        }
        
        isCheckingEndpoint = true
        
        // Call the AppStorageManager method to check the endpoint and fetch models
        storage.checkEndpointAndFetchModels { success in
            self.isCheckingEndpoint = false
            
            if success {
                print("Endpoint validation successful. Found \(storage.availableModels.count) models.")
            } else {
                print("Endpoint validation failed. No valid models found.")
            }
        }
    }
    // Moved helper function inside the struct.
    private func loadConversation(_ conversation: Conversation) {
        if let data = conversation.messages,
           let savedMessages = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            messages = savedMessages
            storage.preferredModel = conversation.model ?? "gpt-4"
            
            // Load system prompt
            storage.systemPrompt = conversation.systemPrompt ?? "You are a helpful assistant."
            
            // Load user prompt if available
            storage.userPrompt = conversation.userPrompt ?? ""
            
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
        var totalTokens = LLMService.estimateTokens(in: storage.systemPrompt) // System prompt
        
        // Add user prompt tokens if present
        if !storage.userPrompt.isEmpty {
            totalTokens += LLMService.estimateTokens(in: storage.userPrompt)
        }
        
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
            // Make sure we have a valid endpoint before trying to save
            let endpoint = storage.hasValidEndpoint ? storage.apiEndpoint : ""
            
            do {
                let savedID = try CoreDataManager.shared.saveConversation(
                    model: storage.preferredModel,
                    systemPrompt: storage.systemPrompt,
                    userPrompt: storage.userPrompt,
                    language: selectedLanguage,
                    messages: messages,
                    apiToken: storage.apiToken,
                    apiEndpoint: endpoint,
                    conversationID: currentConversationID
                )
                print("Successfully saved conversation with ID: \(String(describing: savedID))")
            } catch {
                print("Failed to save conversation: \(error)")
            }
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
    
    // MARK: - Prompt Selector Helpers
    
    // Helper method to check if a prompt is currently selected
    private func isCurrentPromptSelected(_ prompt: SavedPrompt) -> Bool {
        return storage.systemPrompt == prompt.systemPrompt && 
               storage.userPrompt == prompt.userPrompt
    }
    
    // Helper method to get the name of the currently selected prompt
    private func getCurrentPromptName() -> String {
        if let currentPrompt = storage.savedPrompts.first(where: { isCurrentPromptSelected($0) }) {
            return currentPrompt.name
        }
        return "Custom Prompt"
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
