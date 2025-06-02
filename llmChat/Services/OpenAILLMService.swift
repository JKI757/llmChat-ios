import Foundation
import Combine

/// Service for handling interactions with the OpenAI API
final class OpenAILLMService: LLMServiceProtocol {
    // MARK: - Properties
    
    private let apiKey: String
    private let organizationID: String?
    private let baseURL: URL
    private var currentTask: Task<Void, Never>?
    @Published private(set) var status: ServiceStatus = .idle
    
    // MARK: - Initialization
    
    /// Initializes the OpenAILLMService with an API key and optional organization ID
    /// - Parameters:
    ///   - apiKey: The OpenAI API key
    ///   - organizationID: Optional organization ID
    ///   - baseURLString: The base URL for the API, defaults to OpenAI's API URL
    init(apiKey: String, organizationID: String? = nil, baseURLString: String = "https://api.openai.com") {
        self.apiKey = apiKey
        self.organizationID = organizationID
        
        // Ensure the URL ends with /v1 for OpenAI compatibility
        let normalizedURL = baseURLString.hasSuffix("/v1") ? baseURLString : baseURLString.hasSuffix("/") ? baseURLString + "v1" : baseURLString + "/v1"
        self.baseURL = URL(string: normalizedURL)!
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
                    
                    // Prepare messages array for OpenAI
                    var messages: [[String: Any]] = []
                    
                    // Add conversation history
                    for chatMessage in history {
                        // Handle different content types
                        switch chatMessage.content {
                        case .text(let textContent):
                            messages.append([
                                "role": chatMessage.role,
                                "content": textContent
                            ])
                        case .image(let base64Image):
                            // Skip image-only messages in history for regular chat completion
                            // Or you could include a placeholder text
                            messages.append([
                                "role": chatMessage.role,
                                "content": "[Image]"
                            ])
                        }
                    }
                    
                    // Add the new message
                    messages.append([
                        "role": "user",
                        "content": message
                    ])
                    
                    // Create the request body
                    let requestBody: [String: Any] = [
                        "model": model,
                        "messages": messages,
                        "temperature": temperature,
                        "stream": true
                    ]
                    
                    // Create the request
                    var request = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
                    request.httpMethod = "POST"
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    if let organizationID = organizationID, !organizationID.isEmpty {
                        request.addValue(organizationID, forHTTPHeaderField: "OpenAI-Organization")
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                    
                    // Create the session
                    let session = URLSession.shared
                    
                    // Send the request
                    let (data, response) = try await session.data(for: request)
                    
                    // Check the response
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw NSError(domain: "OpenAILLMService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                    }
                    
                    guard httpResponse.statusCode == 200 else {
                        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                        throw NSError(domain: "OpenAILLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
                    }
                    
                    // Parse the response
                    if let responseString = String(data: data, encoding: .utf8) {
                        // Split the response by lines
                        let lines = responseString.components(separatedBy: "\n")
                        
                        for line in lines {
                            // Skip empty lines
                            guard !line.isEmpty else { continue }
                            
                            // Skip data: [DONE] lines
                            guard !line.contains("[DONE]") else { continue }
                            
                            // Remove "data: " prefix
                            let jsonString = line.replacingOccurrences(of: "data: ", with: "")
                            
                            // Parse the JSON
                            if let jsonData = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let firstChoice = choices.first,
                               let delta = firstChoice["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
                            }
                        }
                    }
                    
                    // Finish the stream when complete
                    continuation.finish()
                    
                    // Update status
                    await MainActor.run { self.status = .idle }
                } catch {
                    continuation.finish(throwing: error)
                    await MainActor.run { self.status = .error(error.localizedDescription) }
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
                    
                    // Prepare messages array for OpenAI
                    var messages: [[String: Any]] = []
                    
                    // Add system prompt if provided
                    if !systemPrompt.isEmpty {
                        messages.append([
                            "role": "system",
                            "content": systemPrompt
                        ])
                    }
                    
                    // Add conversation history
                    for chatMessage in history {
                        // Handle different content types
                        switch chatMessage.content {
                        case .text(let textContent):
                            messages.append([
                                "role": chatMessage.role,
                                "content": textContent
                            ])
                        case .image(let base64Image):
                            // Skip image-only messages in history for regular chat completion
                            // Or you could include a placeholder text
                            messages.append([
                                "role": chatMessage.role,
                                "content": "[Image]"
                            ])
                        }
                    }
                    
                    // Add the new message with user prompt if provided
                    let finalUserMessage = userPrompt.isEmpty ? message : userPrompt.replacingOccurrences(of: "{message}", with: message)
                    messages.append([
                        "role": "user",
                        "content": finalUserMessage
                    ])
                    
                    // Create the request body
                    let requestBody: [String: Any] = [
                        "model": model,
                        "messages": messages,
                        "temperature": temperature,
                        "stream": true
                    ]
                    
                    // Create the request
                    var request = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
                    request.httpMethod = "POST"
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    if let organizationID = organizationID, !organizationID.isEmpty {
                        request.addValue(organizationID, forHTTPHeaderField: "OpenAI-Organization")
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                    
                    // Create the session
                    let session = URLSession.shared
                    
                    // Send the request
                    let (data, response) = try await session.data(for: request)
                    
                    // Check the response
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw NSError(domain: "OpenAILLMService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                    }
                    
                    guard httpResponse.statusCode == 200 else {
                        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                        throw NSError(domain: "OpenAILLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
                    }
                    
                    // Parse the response
                    if let responseString = String(data: data, encoding: .utf8) {
                        // Split the response by lines
                        let lines = responseString.components(separatedBy: "\n")
                        
                        for line in lines {
                            // Skip empty lines
                            guard !line.isEmpty else { continue }
                            
                            // Skip data: [DONE] lines
                            guard !line.contains("[DONE]") else { continue }
                            
                            // Remove "data: " prefix
                            let jsonString = line.replacingOccurrences(of: "data: ", with: "")
                            
                            // Parse the JSON
                            if let jsonData = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let firstChoice = choices.first,
                               let delta = firstChoice["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
                            }
                        }
                    }
                    
                    // Finish the stream when complete
                    continuation.finish()
                    
                    // Update status
                    await MainActor.run { self.status = .idle }
                } catch {
                    continuation.finish(throwing: error)
                    await MainActor.run { self.status = .error(error.localizedDescription) }
                }
            }
        }
    }
    
    func getAvailableModels() async throws -> [String] {
        // Default models for OpenAI
        return [
            "gpt-3.5-turbo",
            "gpt-3.5-turbo-16k",
            "gpt-4",
            "gpt-4-turbo",
            "gpt-4-32k"
        ]
        .filter { $0.contains("gpt") } // Only return GPT models
        .sorted()
    }
    
    func cancelRequest() {
        currentTask?.cancel()
        currentTask = nil
        Task { @MainActor in
            status = .idle
        }
    }
}
