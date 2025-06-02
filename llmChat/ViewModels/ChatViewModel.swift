import Foundation
import Combine
import SwiftUI

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isSending: Bool = false
    @Published var errorMessage: String?
    @Published var showingError: Bool = false
    @Published var selectedModel: String = "gpt-3.5-turbo"
    @Published var selectedEndpoint: UUID?
    @Published var availableModels: [String] = []
    @Published var isLoadingModels: Bool = false
    @Published var temperature: Double = 0.7
    
    private var storage: AppStorageManager
    private var currentTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    // Service for the current endpoint
    private var currentService: (any LLMServiceProtocol)?
    
    init(storage: AppStorageManager = .shared) {
        self.storage = storage
        
        // Observe changes to the selected endpoint
        $selectedEndpoint
            .compactMap { $0 }
            .sink { [weak self] endpointID in
                self?.updateSelectedEndpoint(endpointID)
            }
            .store(in: &cancellables)
        
        // Set initial selected endpoint
        if let defaultID = storage.defaultEndpointID {
            selectedEndpoint = defaultID
        } else if let firstEndpoint = storage.savedEndpoints.first {
            selectedEndpoint = firstEndpoint.id
        }
    }
    
    // MARK: - Public Methods
    
    func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let userMessage = ChatMessage(content: inputText, role: "user")
        messages.append(userMessage)
        
        // Clear input field
        let prompt = inputText
        inputText = ""
        
        // Start loading indicator
        isSending = true
        
        // Create a placeholder for the assistant's response
        let assistantMessage = ChatMessage(content: "", role: "assistant")
        messages.append(assistantMessage)
        
        // Cancel any existing task
        currentTask?.cancel()
        currentService?.cancelRequest()
        
        // Start a new task for the API call
        currentTask = Task {
            do {
                guard let service = currentService else {
                    throw ChatError.noServiceAvailable
                }
                
                // Get history without the last empty message
                let history = Array(messages.dropLast())
                
                // Get system prompt and user prompt from storage
                let systemPromptText = storage.systemPrompt
                let userPromptText = storage.userPrompt
                
                // Stream the response
                var fullResponse = ""
                
                // Use the extended service method that supports system and user prompts
                let stream = try await service.sendMessage(
                    prompt,
                    systemPrompt: systemPromptText,
                    userPrompt: userPromptText,
                    model: selectedModel,
                    temperature: temperature,
                    history: history
                )
                
                // Process the stream
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    
                    // Update message
                    fullResponse += chunk
                    updateLastMessage(with: fullResponse)
                }
                
                if !Task.isCancelled {
                    // Save the conversation if needed
                    saveConversationIfNeeded()
                }
            } catch {
                if !Task.isCancelled {
                    handleError(error)
                }
            }
            
            if !Task.isCancelled {
                isSending = false
            }
        }
    }
    
    func cancelRequest() {
        currentTask?.cancel()
        isSending = false
    }
    
    func clearConversation() {
        messages.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func updateSelectedEndpoint(_ endpointID: UUID) {
        // Access the endpoints through the storage manager
        let endpoints = storage.savedEndpoints
        guard let endpoint = endpoints.first(where: { $0.id == endpointID }) else {
            return
        }
        
        do {
            // Create the appropriate service for this endpoint
            let token = endpoint.requiresAuth ? storage.getToken(for: endpointID) : nil
            currentService = try LLMServiceFactory.createService(endpoint: endpoint, apiToken: token)
            
            // Update available models
            updateAvailableModels(for: endpoint)
        } catch {
            handleError(error)
        }
    }
    
    private func updateAvailableModels(for endpoint: SavedEndpoint) {
        guard endpoint.endpointType != .localModel else {
            // For local models, we only have the one model
            availableModels = [endpoint.defaultModel]
            selectedModel = endpoint.defaultModel
            return
        }
        
        // For remote endpoints, fetch available models
        Task {
            do {
                isLoadingModels = true
                let models = try await currentService?.getAvailableModels() ?? []
                
                await MainActor.run {
                    self.availableModels = models
                    if !models.isEmpty {
                        self.selectedModel = models.contains(endpoint.defaultModel) ? endpoint.defaultModel : models[0]
                    }
                    self.isLoadingModels = false
                }
            } catch {
                await MainActor.run {
                    self.availableModels = [endpoint.defaultModel]
                    self.selectedModel = endpoint.defaultModel
                    self.isLoadingModels = false
                }
                self.handleError(error)
            }
        }
    }
    
    private func prepareMessages(for newMessage: String) -> [ChatMessage] {
        // Get the last 10 messages for context
        let contextMessages = Array(messages.suffix(10))
        return contextMessages
    }
    
    private func updateLastMessage(with content: String) {
        guard !messages.isEmpty else { return }
        messages[messages.count - 1] = ChatMessage(content: content, role: "assistant", isError: false)
    }
    
    private func saveConversationIfNeeded() {
        do {
            try storage.coreDataManager.saveConversation(
                model: selectedModel,
                systemPrompt: storage.systemPrompt,
                userPrompt: storage.userPrompt,
                language: "English",
                endpointID: selectedEndpoint,
                messages: messages
            )
        } catch {
            print("Failed to save conversation: \(error)")
        }
    }
    
    private func handleError(_ error: Error) {
        let message: String
        
        switch error {
        case let chatError as ChatError:
            message = chatError.localizedDescription
        case let urlError as URLError:
            message = "Network error: \(urlError.localizedDescription)"
        case let decodingError as DecodingError:
            message = "Failed to decode response: \(decodingError.localizedDescription)"
        default:
            message = error.localizedDescription
        }
        
        errorMessage = message
        showingError = true
        isSending = false
        
        // Update the last message to show the error
        if !messages.isEmpty {
            messages[messages.count - 1] = ChatMessage(
                content: "Error: \(message)", 
                role: "assistant", 
                isError: true
            )
        }
    }
}

// MARK: - Error Handling

enum ChatError: LocalizedError {
    case noServiceAvailable
    case invalidEndpoint(String)
    case apiError(String)
    case unauthorized
    case invalidResponse
    case invalidModel
    
    var errorDescription: String? {
        switch self {
        case .noServiceAvailable:
            return "No chat service is available. Please configure an endpoint in settings."
        case .invalidEndpoint(let url):
            return "Invalid API endpoint: \(url)"
        case .apiError(let message):
            return "API error: \(message)"
        case .unauthorized:
            return "Unauthorized. Please check your API token."
        case .invalidResponse:
            return "Invalid response from the server."
        case .invalidModel:
            return "The selected model is not available."
        }
    }
}
