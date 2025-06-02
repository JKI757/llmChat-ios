import Foundation
import CoreData

/// Legacy service class for backward compatibility
/// This class is being phased out in favor of the new LLMServiceProtocol implementations
class LLMService: NSObject, LLMServiceProtocol {
    // MARK: - Properties
    
    private var service: (any LLMServiceProtocol)?
    private var onUpdate: ((String, Bool) -> Void)?
    private var currentTask: Task<Void, Never>?
    
    // MARK: - LLMServiceProtocol Properties
    @Published private(set) var status: ServiceStatus = .idle
    
    // MARK: - Constants
    
    static let MAX_TOKENS = 4096 // Default max tokens, will be overridden based on model
    static let TOKENS_PER_MESSAGE = 4 // Approx overhead per message
    static let TOKENS_PER_CHAR = 0.25 // Rough approximation for token estimation
    
    // MARK: - Static Methods
    
    /// Get max tokens for a given model
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
    
    /// Estimate tokens in a string
    static func estimateTokens(in text: String) -> Int {
        return Int(Double(text.count) * TOKENS_PER_CHAR) + TOKENS_PER_MESSAGE
    }
    
    /// Creates a service and sends a streaming message
    /// - Parameters:
    ///   - message: The message to send
    ///   - systemPrompt: System prompt for context
    ///   - userPrompt: User prompt template
    ///   - model: The model to use
    ///   - apiToken: API token for authentication
    ///   - endpoint: Endpoint URL
    ///   - preferredLanguage: Preferred language for responses
    ///   - useChatEndpoint: Whether to use chat completions endpoint
    ///   - temperature: Temperature for generation
    ///   - conversationHistory: Previous conversation history
    ///   - onUpdate: Callback for updates
    /// - Returns: The service instance
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
        let service = LLMService()
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
    
    // MARK: - Instance Methods
    
    /// Cancels the current streaming request
    func cancelStreaming() {
        currentTask?.cancel()
        service?.cancelRequest()
    }
    
    /// Starts streaming a response from the LLM
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
        // Create a temporary endpoint configuration
        let endpointConfig = createEndpointConfig(endpoint: endpoint, apiToken: apiToken, model: model)
        
        // Cancel any existing task
        currentTask?.cancel()
        
        // Create a new task for the API call
        currentTask = Task {
            do {
                // Create the service
                self.service = try createService(endpointConfig: endpointConfig, apiToken: apiToken)
                
                guard let service = self.service else {
                    throw ServiceError.serviceCreationFailed
                }
                
                // Enhance system prompt with language preference if needed
                var finalSystemPrompt = systemPrompt
                if preferredLanguage != "English" {
                    finalSystemPrompt += "\n\nYou MUST ONLY and ALWAYS respond in \(preferredLanguage), regardless of the language the user uses to communicate with you. NEVER respond in any other language under any circumstances."
                }
                
                // Stream the response
                let stream = try await service.sendMessage(
                    message,
                    systemPrompt: finalSystemPrompt,
                    userPrompt: userPrompt,
                    model: model,
                    temperature: temperature,
                    history: conversationHistory
                )
                
                // Process the stream
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    
                    // Call the update handler
                    await MainActor.run {
                        self.onUpdate?(chunk, false)
                    }
                }
                
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.onUpdate?("Error: \(error.localizedDescription)", true)
                    }
                }
            }
        }
    }
    
    /// Creates a temporary endpoint configuration for legacy compatibility
    private func createEndpointConfig(endpoint: String, apiToken: String, model: String) -> SavedEndpoint {
        // Normalize the endpoint URL
        var finalEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure endpoint has a valid scheme
        if !finalEndpoint.hasPrefix("http://") && !finalEndpoint.hasPrefix("https://") {
            finalEndpoint = "https://" + finalEndpoint
        }
        
        // Remove trailing slash if present
        finalEndpoint = finalEndpoint.hasSuffix("/") ? String(finalEndpoint.dropLast()) : finalEndpoint
        
        // Determine endpoint type
        let endpointType: EndpointType
        if finalEndpoint.contains("openai.com") {
            endpointType = .openAI
        } else if finalEndpoint.hasPrefix("file://") || finalEndpoint.lowercased().hasSuffix(".gguf") {
            endpointType = .localModel
        } else {
            endpointType = .customAPI
        }
        
        // Create a temporary endpoint configuration
        return SavedEndpoint(
            id: UUID(),
            name: "Temporary Endpoint",
            url: finalEndpoint,
            defaultModel: model,
            maxTokens: LLMService.getMaxTokensForModel(model),
            requiresAuth: !apiToken.isEmpty,
            organizationID: nil,
            endpointType: endpointType
        )
    }
    
    /// Creates a service based on the endpoint configuration
    private func createService(endpointConfig: SavedEndpoint, apiToken: String) throws -> any LLMServiceProtocol {
        return try LLMServiceFactory.createService(endpoint: endpointConfig, apiToken: apiToken)
    }
    
    // MARK: - LLMServiceProtocol Implementation
    
    func sendMessage(
        _ message: String,
        model: String,
        temperature: Double,
        history: [ChatMessage]
    ) async throws -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            self.currentTask = Task {
                // Use the wrapper to handle the legacy implementation
                let endpoint = self.service?.status == .idle ? "" : "default"
                let _ = LLMService.sendStreamingMessage(
                    message: message,
                    systemPrompt: "",
                    userPrompt: "",
                    model: model,
                    apiToken: "", // Will be handled by the service
                    endpoint: endpoint,
                    preferredLanguage: "",
                    useChatEndpoint: true,
                    temperature: temperature,
                    conversationHistory: history
                ) { chunk, isComplete in
                    if isComplete {
                        continuation.finish()
                    } else {
                        continuation.yield(chunk)
                    }
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
        return AsyncThrowingStream { continuation in
            self.currentTask = Task {
                // Use the wrapper to handle the legacy implementation
                let endpoint = self.service?.status == .idle ? "" : "default"
                let _ = LLMService.sendStreamingMessage(
                    message: message,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    model: model,
                    apiToken: "", // Will be handled by the service
                    endpoint: endpoint,
                    preferredLanguage: "",
                    useChatEndpoint: true,
                    temperature: temperature,
                    conversationHistory: history
                ) { chunk, isComplete in
                    if isComplete {
                        continuation.finish()
                    } else {
                        continuation.yield(chunk)
                    }
                }
            }
        }
    }
    
    func cancelRequest() {
        currentTask?.cancel()
        service?.cancelRequest()
    }
    
    func getAvailableModels() async throws -> [String] {
        // Default implementation for legacy service
        return ["gpt-3.5-turbo", "gpt-4"]
    }
    
    // MARK: - Error Types
    
    enum ServiceError: LocalizedError {
        case invalidEndpoint(String)
        case modelNotFound(String)
        case missingToken
        case serviceCreationFailed
        
        var errorDescription: String? {
            switch self {
            case .invalidEndpoint(let url):
                return "Invalid endpoint URL: \(url)"
            case .modelNotFound(let model):
                return "Model not found: \(model)"
            case .missingToken:
                return "API token is required but not provided"
            case .serviceCreationFailed:
                return "Failed to create LLM service"
            }
        }
    }
}
