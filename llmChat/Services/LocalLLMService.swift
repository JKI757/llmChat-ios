import Foundation
import LLM

/// Service for handling local LLM execution using LLM.swift
final class LocalLLMService: LLMServiceProtocol {
    // MARK: - Properties
    
    private var llm: LLM?
    private var currentTask: Task<Void, Never>?
    private let modelURL: URL
    private let maxTokens: Int
    @Published private(set) var status: ServiceStatus = .idle
    
    // MARK: - Initialization
    
    /// Initializes the LocalLLMService with a local model file
    /// - Parameters:
    ///   - modelURL: URL to the local GGUF model file
    ///   - maxTokens: Maximum number of tokens to generate (default: 2048)
    init(modelURL: URL, maxTokens: Int = 2048) {
        self.modelURL = modelURL
        self.maxTokens = maxTokens
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
                    
                    // Initialize LLM if needed
                    if self.llm == nil {
                        try await self.initializeLLM()
                    }
                    
                    guard let llm = self.llm else {
                        throw LLMError.modelNotInitialized
                    }
                    
                    // Build prompt from history
                    var promptParts = [String]()
                    
                    // Add conversation history
                    for chatMessage in history {
                        promptParts.append("\(chatMessage.role): \(chatMessage.content)")
                    }
                    
                    // Add current message
                    promptParts.append("user: \(message)")
                    
                    // Create final prompt
                    let prompt = promptParts.joined(separator: "\n")
                    
                    // Process the message using respond method
                    await llm.respond(to: prompt) { stream in
                        var result = ""
                        for await chunk in stream {
                            guard !Task.isCancelled else { break }
                            continuation.yield(chunk)
                            result += chunk
                        }
                        return result
                    }
                    
                    continuation.finish()
                    await MainActor.run { self.status = .idle }
                } catch {
                    if !Task.isCancelled {
                        continuation.finish(throwing: error)
                        await MainActor.run { self.status = .error(error.localizedDescription) }
                    }
                }
            }
        }
    }
    
    /// Extended version of sendMessage that supports system and user prompts
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
                    
                    // Initialize LLM if needed
                    if self.llm == nil {
                        try await self.initializeLLM()
                    }
                    
                    guard let llm = self.llm else {
                        throw LLMError.modelNotInitialized
                    }
                    
                    // Build prompt from history
                    var promptParts = [String]()
                    
                    // Add system prompt if provided
                    if !systemPrompt.isEmpty {
                        promptParts.append("system: \(systemPrompt)")
                    }
                    
                    // Add conversation history
                    for chatMessage in history {
                        promptParts.append("\(chatMessage.role): \(chatMessage.content)")
                    }
                    
                    // Add current message with user prompt if provided
                    let finalUserMessage = userPrompt.isEmpty ? message : userPrompt.replacingOccurrences(of: "{message}", with: message)
                    promptParts.append("user: \(finalUserMessage)")
                    
                    // Create final prompt
                    let prompt = promptParts.joined(separator: "\n")
                    
                    // Process the message using respond method
                    await llm.respond(to: prompt) { stream in
                        var result = ""
                        for await chunk in stream {
                            guard !Task.isCancelled else { break }
                            continuation.yield(chunk)
                            result += chunk
                        }
                        return result
                    }
                    
                    continuation.finish()
                    await MainActor.run { self.status = .idle }
                } catch {
                    if !Task.isCancelled {
                        continuation.finish(throwing: error)
                        await MainActor.run { self.status = .error(error.localizedDescription) }
                    }
                }
            }
        }
    }
    
    func cancelRequest() {
        currentTask?.cancel()
        currentTask = nil
        llm?.stop()
        status = .idle
    }
    
    func getAvailableModels() async throws -> [String] {
        // For local service, we only have the currently loaded model
        return [modelURL.lastPathComponent]
    }
    
    // MARK: - Private Methods
    
    private func initializeLLM() async throws {
        do {
            // Initialize LLM with the correct path parameter
            llm = LLM(
                from: modelURL.path,
                stopSequence: nil,
                history: [],
                seed: .random(in: .min ... .max),
                topK: 40,
                topP: 0.95,
                temp: 0.8,
                historyLimit: 8,
                maxTokenCount: Int32(maxTokens)
            )
            
            if llm == nil {
                throw LLMError.initializationFailed("Failed to initialize model")
            }
        } catch {
            throw LLMError.initializationFailed(error.localizedDescription)
        }
    }
}

// MARK: - Error Handling

enum LLMError: LocalizedError {
    case modelNotInitialized
    case initializationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotInitialized:
            return "Model failed to initialize"
        case .initializationFailed(let message):
            return "Failed to initialize model: \(message)"
        }
    }
}
