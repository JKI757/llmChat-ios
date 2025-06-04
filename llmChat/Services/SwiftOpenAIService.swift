import Foundation
import Combine
import SwiftOpenAI

/// Service for handling interactions with the OpenAI API using SwiftOpenAI library
final class SwiftOpenAIService: LLMServiceProtocol {
    // MARK: - Properties
    
    private let service: OpenAIService
    private let apiKey: String
    private let organizationID: String?
    private let baseURL: URL
    private var currentTask: Task<Void, Never>?
    @Published private(set) var status: ServiceStatus = .idle
    
    // MARK: - Initialization
    
    /// Initializes the SwiftOpenAIService with an API key and optional organization ID
    /// - Parameters:
    ///   - apiKey: The OpenAI API key
    ///   - organizationID: Optional organization ID
    ///   - baseURLString: The base URL for the API, defaults to OpenAI's API URL
    init(apiKey: String, organizationID: String? = nil, baseURLString: String = "https://api.openai.com") {
        self.apiKey = apiKey
        self.organizationID = organizationID
        self.baseURL = URL(string: baseURLString)!
        self.service = OpenAIServiceFactory.service(apiKey: apiKey, organizationID: organizationID)
    }
    
    // MARK: - Helper Methods
    
    /// Converts a string role to the appropriate role string for the API
    /// - Parameter role: String representation of the role
    /// - Returns: Role string for the API
    private func convertToRole(_ role: String) -> String {
        switch role.lowercased() {
        case "system":
            return "system"
        case "assistant":
            return "assistant"
        case "user":
            return "user"
        default:
            return "user"
        }
    }
    
    /// Wraps an error with a consistent domain and code
    /// - Parameter error: The original error
    /// - Returns: A wrapped NSError
    private func wrapError(_ error: Error) -> NSError {
        return NSError(
            domain: "SwiftOpenAIService",
            code: (error as NSError).code,
            userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
        )
    }
    
    /// Creates a streaming chat completion with any model name
    /// - Parameters:
    ///   - messages: Array of message dictionaries with role and content
    ///   - modelName: The exact model name to use
    ///   - temperature: Optional temperature parameter
    /// - Returns: An async stream of text chunks
    private func createStreamedChat(
        messages: [[String: Any]],
        modelName: String,
        temperature: Double? = nil
    ) async throws -> AsyncThrowingStream<String, Error> {
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        
        // Set headers
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let organizationID = organizationID {
            request.setValue(organizationID, forHTTPHeaderField: "OpenAI-Organization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Prepare request body
        var requestBody: [String: Any] = [
            "messages": messages,
            "model": modelName,
            "stream": true
        ]
        
        if let temperature = temperature {
            requestBody["temperature"] = temperature
        }
        
        // Encode request body
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Create URLSession and data task
        let (result, _) = try await URLSession.shared.bytes(for: request)
        
        // Return async stream of text chunks
        return AsyncThrowingStream<String, Error> { continuation in
            Task {
                do {
                    for try await line in result.lines {
                        guard !line.isEmpty else { continue }
                        
                        // SSE format: lines start with "data: "
                        guard line.hasPrefix("data: ") else { continue }
                        
                        // Extract the JSON part
                        let jsonString = line.dropFirst(6)
                        
                        // Check for the end of the stream
                        if jsonString == "[DONE]" {
                            continuation.finish()
                            break
                        }
                        
                        // Parse the JSON to extract the content
                        if let data = jsonString.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let choices = json["choices"] as? [[String: Any]],
                           let firstChoice = choices.first,
                           let delta = firstChoice["delta"] as? [String: Any],
                           let content = delta["content"] as? String {
                            continuation.yield(content)
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - LLMServiceProtocol Implementation
    
    func sendMessage(
        _ message: String,
        model: String,
        temperature: Double,
        history: [ChatMessage]
    ) async throws -> AsyncThrowingStream<String, Error> {
        // Cancel any existing task
        cancelRequest()
        
        return AsyncThrowingStream<String, Error> { continuation in
            self.currentTask = Task {
                do {
                    // Update status
                    await MainActor.run { self.status = .streaming }
                    
                    // Convert app's ChatMessage to API format
                    var messages: [[String: Any]] = []
                    
                    // Add conversation history
                    for chatMessage in history {
                        let role = convertToRole(chatMessage.role)
                        
                        switch chatMessage.content {
                        case .text(let text):
                            messages.append([
                                "role": role,
                                "content": text
                            ])
                        case .image(let base64Image):
                            // Only handle images from user messages
                            if chatMessage.role == "user" {
                                let imageURL = "data:image/jpeg;base64,\(base64Image)"
                                messages.append([
                                    "role": role,
                                    "content": [
                                        ["type": "text", "text": ""],
                                        ["type": "image_url", "image_url": ["url": imageURL]]
                                    ]
                                ])
                            }
                        }
                    }
                    
                    // Add the current message
                    messages.append([
                        "role": "user",
                        "content": message
                    ])
                    
                    // Create a direct streaming request with the exact model name
                    let stream = try await createStreamedChat(
                        messages: messages,
                        modelName: model,
                        temperature: temperature
                    )
                    
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    
                    continuation.finish()
                    
                    // Update status
                    await MainActor.run { self.status = .idle }
                } catch {
                    let wrappedError = wrapError(error)
                    continuation.finish(throwing: wrappedError)
                    await MainActor.run { self.status = .error(wrappedError.localizedDescription) }
                }
            }
        }
    }
    
    func sendMessage(
        _ message: String,
        systemPrompt: String,
        userPrompt: String,
        model: String,
        temperature: Double,
        history: [ChatMessage]
    ) async throws -> AsyncThrowingStream<String, Error> {
        // Cancel any existing task
        cancelRequest()
        
        return AsyncThrowingStream<String, Error> { continuation in
            self.currentTask = Task {
                do {
                    // Update status
                    await MainActor.run { self.status = .streaming }
                    
                    // Convert app's ChatMessage to API format
                    var messages: [[String: Any]] = []
                    
                    // Add system prompt
                    if !systemPrompt.isEmpty {
                        messages.append([
                            "role": "system",
                            "content": systemPrompt
                        ])
                    }
                    
                    // Add conversation history
                    for chatMessage in history {
                        let role = convertToRole(chatMessage.role)
                        
                        switch chatMessage.content {
                        case .text(let text):
                            messages.append([
                                "role": role,
                                "content": text
                            ])
                        case .image(let base64Image):
                            // Only handle images from user messages
                            if chatMessage.role == "user" {
                                let imageURL = "data:image/jpeg;base64,\(base64Image)"
                                messages.append([
                                    "role": role,
                                    "content": [
                                        ["type": "text", "text": ""],
                                        ["type": "image_url", "image_url": ["url": imageURL]]
                                    ]
                                ])
                            }
                        }
                    }
                    
                    // Add the current message with user prompt if provided
                    let finalUserMessage = userPrompt.isEmpty ? message : userPrompt.replacingOccurrences(of: "{input}", with: message)
                    messages.append([
                        "role": "user",
                        "content": finalUserMessage
                    ])
                    
                    // Create a direct streaming request with the exact model name
                    let stream = try await createStreamedChat(
                        messages: messages,
                        modelName: model,
                        temperature: temperature
                    )
                    
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    
                    continuation.finish()
                    
                    // Update status
                    await MainActor.run { self.status = .idle }
                } catch {
                    let wrappedError = wrapError(error)
                    continuation.finish(throwing: wrappedError)
                    await MainActor.run { self.status = .error(wrappedError.localizedDescription) }
                }
            }
        }
    }
    
    func cancelRequest() {
        currentTask?.cancel()
        currentTask = nil
        Task { @MainActor in
            status = .idle
        }
    }
    
    func getAvailableModels() async throws -> [String] {
        do {
            let modelsResponse = try await service.listModels()
            return modelsResponse.data.map { $0.id }
        } catch {
            // Fallback to default models if API call fails
            return [
                "gpt-4",
                "gpt-4-turbo",
                "gpt-3.5-turbo",
                "gpt-3.5-turbo-16k"
            ]
        }
    }
    
    func sendMessages(_ messages: [ChatMessage], stream: Bool, model: String? = nil, temperature: Double? = nil) async throws -> String {
        // Cancel any existing task
        cancelRequest()
        
        // Update status
        await MainActor.run { self.status = .streaming }
        
        // Prepare messages array for OpenAI
        var apiMessages: [[String: Any]] = []
        
        // Add all messages
        for chatMessage in messages {
            apiMessages.append([
                "role": convertToRole(chatMessage.role),
                "content": chatMessage.content.textValue
            ])
        }
        
        // If streaming is requested, use the streaming API and collect all chunks
        if stream {
            var fullResponse = ""
            let streamingResponse = try await createStreamedChat(
                messages: apiMessages,
                modelName: model ?? "gpt-3.5-turbo", // Use provided model or default
                temperature: temperature ?? 0.7 // Use provided temperature or default
            )
            
            for try await chunk in streamingResponse {
                fullResponse += chunk
            }
            
            // Update status when done
            await MainActor.run { self.status = .idle }
            return fullResponse
        }
        
        // For non-streaming, make a direct API call
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        
        // Set headers
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let organizationID = organizationID {
            request.setValue(organizationID, forHTTPHeaderField: "OpenAI-Organization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Prepare request body
        let requestBody: [String: Any] = [
            "messages": apiMessages,
            "model": model ?? "gpt-3.5-turbo", // Use provided model or default
            "temperature": temperature ?? 0.7, // Use provided temperature or default
            "stream": false
        ]
        
        // Encode request body
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Make the request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check the response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "SwiftOpenAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "SwiftOpenAIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
        
        // Parse the response
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {
            // Update status when done
            await MainActor.run { self.status = .idle }
            return content
        } else {
            throw NSError(domain: "SwiftOpenAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
        }
    }
}
