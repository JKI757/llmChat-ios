import Foundation
import CoreData

class LLMService: NSObject, URLSessionDataDelegate {
    private var onUpdate: ((String, Bool) -> Void)?
    private var currentTask: URLSessionDataTask?
    private var useChatEndpoint: Bool
    
    init(useChatEndpoint: Bool) {
        self.useChatEndpoint = useChatEndpoint
        super.init()
    }

    // Constants for context management
    static let MAX_TOKENS = 4096 // Default max tokens, will be overridden based on model
    static let TOKENS_PER_MESSAGE = 4 // Approx overhead per message
    static let TOKENS_PER_CHAR = 0.25 // Rough approximation for token estimation
    
    // Get max tokens for a given model
    static func getMaxTokensForModel(_ model: String) -> Int {
        switch model.lowercased() {
        case _ where model.contains("gpt-4-turbo"):
            return 128000
        case _ where model.contains("gpt-4"):
            return 8192
        case _ where model.contains("gpt-3.5-turbo-16k"):
            return 16384
        case _ where model.contains("gpt-3.5-turbo"):
            return 4096
        default:
            return 4096 // Default fallback
        }
    }
    
    // Estimate tokens in a string
    static func estimateTokens(in text: String) -> Int {
        return Int(Double(text.count) * TOKENS_PER_CHAR) + TOKENS_PER_MESSAGE
    }
    
    static func sendStreamingMessage(
        message: String,
        systemPrompt: String,
        userPrompt: String = "",
        model: String,
        apiToken: String,
        endpoint: String,
        preferredLanguage: String,
        useChatEndpoint: Bool,
        temperature: Double = 1.0,
        conversationHistory: [ChatMessage] = [],
        onUpdate: @escaping (String, Bool) -> Void
    ) -> LLMService {
        let service = LLMService(useChatEndpoint: useChatEndpoint)
        service.onUpdate = onUpdate
        service.startStreaming(
            message: message,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            model: model,
            apiToken: apiToken,
            endpoint: endpoint,
            preferredLanguage: preferredLanguage,
            temperature: temperature,
            conversationHistory: conversationHistory
        )
        return service
    }
    
    func cancelStreaming() {
        currentTask?.cancel()
    }
    
    private func startStreaming(
        message: String,
        systemPrompt: String,
        userPrompt: String = "",
        model: String,
        apiToken: String,
        endpoint: String,
        preferredLanguage: String,
        temperature: Double = 1.0,
        conversationHistory: [ChatMessage] = []
    ) {
        // Check if the endpoint already has the necessary path components
        var finalEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure endpoint has a valid scheme
        if !finalEndpoint.hasPrefix("http://") && !finalEndpoint.hasPrefix("https://") {
            // Default to https, but allow http if specified
            finalEndpoint = "https://" + finalEndpoint
        }
        
        // Check if the endpoint already contains the path
        let chatPath = "/v1/chat/completions"
        let completionsPath = "/v1/completions"
        
        if (useChatEndpoint && finalEndpoint.contains(chatPath)) || 
           (!useChatEndpoint && finalEndpoint.contains(completionsPath)) {
            // The endpoint already has the correct path, use it as is
        } else {
            // Remove trailing slash if present
            finalEndpoint = finalEndpoint.hasSuffix("/") ? String(finalEndpoint.dropLast()) : finalEndpoint
            
            // Add the appropriate path
            let endpointPath = useChatEndpoint ? chatPath : completionsPath
            finalEndpoint += endpointPath
        }
        
        guard let url = URL(string: finalEndpoint) else {
            DispatchQueue.main.async {
                self.onUpdate?("Error: Invalid API endpoint: \(finalEndpoint)", true)
            }
            return
        }
        
        // Create a custom URL session configuration that allows HTTP connections
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.waitsForConnectivity = true
        sessionConfig.timeoutIntervalForRequest = 60.0
        sessionConfig.timeoutIntervalForResource = 300.0
        
        
        // Use the provided system prompt if available, otherwise use a default system prompt
        var finalSystemPrompt = !systemPrompt.isEmpty ? systemPrompt : "You are a helpful assistant."
        
        // If a language other than English is selected, enforce strict language response
        if preferredLanguage != "English" {
            // Add strict language instruction to ensure the model only responds in the selected language
            finalSystemPrompt += "\n\nYou MUST ONLY and ALWAYS respond in \(preferredLanguage), regardless of the language the user uses to communicate with you. NEVER respond in any other language under any circumstances."
        }
        
        // Get max tokens for the model
        let maxTokens = LLMService.getMaxTokensForModel(model)
        
        // Prepare request body based on endpoint type
        let json: [String: Any]
        if useChatEndpoint {
            // Process conversation history with context window management
            var messages: [[String: Any]] = [["role": "system", "content": finalSystemPrompt]]
            
            // Add conversation history if available
            if !conversationHistory.isEmpty {
                let processedHistory = processConversationHistory(conversationHistory, maxTokens: maxTokens, systemPrompt: finalSystemPrompt)
                
                // Add processed history messages
                for historyMessage in processedHistory {
                    // Only include text messages, skip image messages
                    if case .text(let textContent) = historyMessage.content {
                        if historyMessage.isUser {
                            messages.append(["role": "user", "content": textContent])
                        } else {
                            messages.append(["role": "assistant", "content": textContent])
                        }
                    }
                    // Images could be handled here if the API supports it
                }
                
                // Add the current message if it's not already in the history
                // Check if the message is already in the processed history
                let messageExists = processedHistory.contains { historyMessage in
                    if historyMessage.isUser, case .text(let text) = historyMessage.content {
                        return text == message // comparing the text content with the current message string
                    }
                    return false
                }
                
                if !messageExists {
                    // If we have a user prompt, prepend it to the message
                    let finalUserMessage = userPrompt.isEmpty ? message : userPrompt + "\n\n" + message
                    messages.append(["role": "user", "content": finalUserMessage])
                }
            } else {
                // Just add the current message if no history
                // If we have a user prompt, prepend it to the message
                let finalUserMessage = userPrompt.isEmpty ? message : userPrompt + "\n\n" + message
                messages.append(["role": "user", "content": finalUserMessage])
            }
            
            json = [
                "model": model,
                "messages": messages,
                "temperature": temperature,
                "stream": true
            ]
        } else {
            // For non-chat endpoints, combine system prompt, user prompt, and message
            var fullPrompt = finalSystemPrompt
            
            if !userPrompt.isEmpty {
                fullPrompt += "\n\n" + userPrompt
            }
            
            fullPrompt += "\n\n" + message
            
            json = [
                "model": model,
                "prompt": fullPrompt,
                "temperature": temperature,
                "stream": true
            ]
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: json) else {
            DispatchQueue.main.async {
                self.onUpdate?("Failed to encode JSON", true)
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // Set a longer timeout (30 seconds) to accommodate model loading time
        request.timeoutInterval = 30.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authorization header if API token is available
        print("API token received by LLMService: \(apiToken.isEmpty ? "EMPTY" : "\(apiToken.prefix(min(5, apiToken.count)))...")")
        
        let trimmedToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToken.isEmpty {
            request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
            print("Using API token: \(trimmedToken.prefix(min(5, trimmedToken.count)))...\(trimmedToken.suffix(min(5, trimmedToken.count)))")
        } else {
            print("WARNING: No API token provided for request to \(url.absoluteString)")
        }
        
        request.httpBody = jsonData

        // Create a session with a longer timeout configuration that allows HTTP connections
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        
        // Configure session to allow HTTP connections
        if #available(iOS 9.0, *) {
            // This disables ATS for this session only
            config.waitsForConnectivity = true
        }
        
        print("Connecting to endpoint: \(url.absoluteString)")
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        currentTask = session.dataTask(with: request)
        currentTask?.resume()
    }
    
    // URLSessionDataDelegate method to capture streamed data
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let chunkString = String(data: data, encoding: .utf8) {
            // Split the string by newlines to handle multiple events in one chunk
            let lines = chunkString.components(separatedBy: "\n")
            
            for line in lines where !line.isEmpty {
                // Check if this is a completion message with empty delta
                if line.contains("finish_reason\":\"stop\"") {
                    print("Detected completion message with finish_reason: stop")
                }
                
                DispatchQueue.main.async {
                    // Process the chunk based on the endpoint type
                    if self.useChatEndpoint {
                        // Handle OpenAI chat completions format
                        self.onUpdate?(line, false)
                    } else {
                        // Handle non-chat completions format
                        // Some APIs return raw text without the "data: " prefix
                        // Try to detect if this is a JSON response or plain text
                        if line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                            // This is likely JSON, wrap it with "data: " prefix for consistent handling
                            self.onUpdate?("data: " + line, false)
                        } else {
                            // This is likely plain text, just pass it through
                            self.onUpdate?(line, false)
                        }
                    }
                }
            }
        }
    }
    
    // URLSessionTaskDelegate method to signal completion or error
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("Stream error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.onUpdate?("Error: \(error.localizedDescription)", true)
            }
        } else {
            print("Stream completed successfully")
            DispatchQueue.main.async {
                // Send a final [DONE] message to signal completion
                self.onUpdate?("data: [DONE]", true)
            }
        }
    }
    
    // MARK: - Context Window Management
    
    // Process conversation history to fit within context window
    private func processConversationHistory(_ history: [ChatMessage], maxTokens: Int, systemPrompt: String) -> [ChatMessage] {
        // If history is small enough, return it as is
        let systemTokens = LLMService.estimateTokens(in: systemPrompt)
        var totalTokens = systemTokens
        
        for message in history {
            totalTokens += LLMService.estimateTokens(in: message.text)
        }
        
        // If we're under the limit (with some buffer for the response), return the full history
        let tokenBuffer = min(1000, maxTokens / 4) // Reserve 25% or 1000 tokens, whichever is smaller
        if totalTokens <= maxTokens - tokenBuffer {
            return history
        }
        
        // We need to compress the history
        var processedHistory: [ChatMessage] = []
        
        // Always keep the first few messages for context
        let keepAtStart = min(3, history.count)
        processedHistory.append(contentsOf: history.prefix(keepAtStart))
        
        // Always keep the most recent messages
        let keepAtEnd = min(5, history.count - keepAtStart)
        if keepAtEnd > 0 {
            let endMessages = history.suffix(keepAtEnd)
            
            // If we still need to compress, generate a summary of the middle part
            if history.count > keepAtStart + keepAtEnd {
                let middleStart = keepAtStart
                let middleEnd = history.count - keepAtEnd
                
                if middleEnd > middleStart {
                    let middleMessages = Array(history[middleStart..<middleEnd])
                    let summary = createConversationSummary(middleMessages)
                    processedHistory.append(ChatMessage(text: "[Summary of previous conversation: \(summary)]", isUser: false))
                }
            }
            
            // Add the recent messages
            processedHistory.append(contentsOf: endMessages)
        }
        
        return processedHistory
    }
    
    // Create a summary of conversation messages
    private func createConversationSummary(_ messages: [ChatMessage]) -> String {
        var summary = ""
        
        // Simple approach: extract key points from user messages
        for message in messages where message.isUser {
            if case .text(let textContent) = message.content {
                let truncated = String(textContent.prefix(100))
                summary += "\(truncated)\(textContent.count > 100 ? "..." : "")\n"
            } else if case .image(_) = message.content {
                summary += "[Image]\n"
            }
        }
        
        return summary.isEmpty ? "Previous conversation" : summary
    }
    
    // MARK: - Conversation Summarization
    
    // Generate a summary for a conversation using LLM
    static func generateConversationSummary(
        messages: [ChatMessage],
        apiToken: String,
        endpoint: String,
        model: String,
        systemPrompt: String = "",
        userPrompt: String = "",
        completion: @escaping (String) -> Void
    ) {
        // Create a conversation transcript for the LLM to summarize
        var transcript = ""
        for (index, message) in messages.enumerated() {
            let role = message.isUser ? "User" : "Assistant"
            
            switch message.content {
            case .text(let textContent):
                transcript += "\(role): \(textContent)\n\n"
            case .image(_):
                transcript += "\(role): [Image]\n\n"
            }
            
            // If we have just the first exchange, that's enough for a summary
            if index >= 1 && messages.count > 3 {
                break
            }
        }
        
        // Fallback to first user message if we can't connect to LLM
        guard !apiToken.isEmpty, !endpoint.isEmpty else {
            if let firstUserMessage = messages.first(where: { $0.isUser }) {
                if case .text(let textContent) = firstUserMessage.content {
                    let truncated = String(textContent.prefix(50)) + (textContent.count > 50 ? "..." : "")
                    completion(truncated)
                } else if case .image(_) = firstUserMessage.content {
                    completion("Image Conversation")
                } else {
                    completion("New Conversation")
                }
            } else {
                completion("New Conversation")
            }
            return
        }
        
        // Ensure endpoint has a valid scheme
        var baseEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !baseEndpoint.hasPrefix("http://") && !baseEndpoint.hasPrefix("https://") {
            baseEndpoint = "https://" + baseEndpoint
        }
        // Remove trailing slash if present
        baseEndpoint = baseEndpoint.hasSuffix("/") ? String(baseEndpoint.dropLast()) : baseEndpoint
        
        guard let url = URL(string: baseEndpoint + "/v1/chat/completions") else {
            completion("New Conversation")
            return
        }
        
        // Use custom system prompt if provided, otherwise use the default title generation prompt
        let titleSystemPrompt = !systemPrompt.isEmpty 
            ? systemPrompt 
            : "You are a helpful assistant that generates short, concise titles (5 words max) for chat conversations. The title should capture the main topic or question."
        
        // Prepare user content, incorporating custom user prompt if provided
        let userContent = !userPrompt.isEmpty 
            ? "\(userPrompt)\n\nPlease create a short, concise title (5 words max) for this conversation:\n\n\(transcript)" 
            : "Please create a short, concise title (5 words max) for this conversation:\n\n\(transcript)"
        
        let json: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": titleSystemPrompt],
                ["role": "user", "content": userContent]
            ],
            "max_tokens": 20
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: json) else {
            completion("New Conversation")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil,
                  let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = jsonResponse["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                
                // Fallback to first message if API call fails
                DispatchQueue.main.async {
                    if let firstUserMessage = messages.first(where: { $0.isUser })?.text {
                        let truncated = String(firstUserMessage.prefix(50)) + (firstUserMessage.count > 50 ? "..." : "")
                        completion(truncated)
                    } else {
                        completion("New Conversation")
                    }
                }
                return
            }
            
            DispatchQueue.main.async {
                // Clean up the title (remove quotes if present)
                let cleanTitle = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "^\"", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\"$", with: "", options: .regularExpression)
                
                completion(cleanTitle)
            }
        }
        task.resume()
    }
}
