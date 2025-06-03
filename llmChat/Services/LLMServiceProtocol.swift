import Foundation

/// Protocol defining the interface for LLM services
/// This allows for easy swapping between different LLM service implementations
protocol LLMServiceProtocol: ObservableObject {
    /// Sends a basic message to the LLM and returns a stream of response chunks
    /// - Parameters:
    ///   - message: The message to send
    ///   - model: The model to use
    ///   - temperature: Temperature for generation
    ///   - history: Previous conversation history
    /// - Returns: A stream of response chunks
    func sendMessage(
        _ message: String,
        model: String,
        temperature: Double,
        history: [ChatMessage]
    ) async throws -> AsyncThrowingStream<String, Error>
    
    /// Sends a message to the LLM with system and user prompts and returns a stream of response chunks
    /// - Parameters:
    ///   - message: The message to send
    ///   - systemPrompt: Optional system prompt for context
    ///   - userPrompt: Optional user prompt template
    ///   - model: The model to use
    ///   - temperature: Temperature for generation
    ///   - history: Previous conversation history
    /// - Returns: A stream of response chunks
    func sendMessage(
        _ message: String,
        systemPrompt: String,
        userPrompt: String,
        model: String,
        temperature: Double,
        history: [ChatMessage]
    ) async throws -> AsyncThrowingStream<String, Error>
    
    /// Cancels any ongoing request
    func cancelRequest()
    
    /// Fetches available models from the service
    /// - Returns: Array of available model identifiers
    func getAvailableModels() async throws -> [String]
    
    /// Sends a list of messages to the LLM and returns the complete response as a string
    /// - Parameters:
    ///   - messages: The messages to send
    ///   - stream: Whether to stream the response (false returns complete response)
    ///   - model: The model to use (optional, uses service default if not specified)
    ///   - temperature: Temperature for generation (optional, uses service default if not specified)
    /// - Returns: The complete response as a string
    func sendMessages(_ messages: [ChatMessage], stream: Bool, model: String?, temperature: Double?) async throws -> String
    
    /// The current status of the service
    var status: ServiceStatus { get }
}

// Extension to provide backward compatibility
extension LLMServiceProtocol {
    func sendMessages(_ messages: [ChatMessage], stream: Bool) async throws -> String {
        return try await sendMessages(messages, stream: stream, model: nil, temperature: nil)
    }
}

/// Represents the current status of the LLM service
enum ServiceStatus: Equatable {
    case idle
    case loading
    case streaming
    case error(String)
}

// MARK: - Default Implementations
extension LLMServiceProtocol {
    var status: ServiceStatus { .idle }
}
