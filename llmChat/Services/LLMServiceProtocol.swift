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
    
    /// The current status of the service
    var status: ServiceStatus { get }
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
