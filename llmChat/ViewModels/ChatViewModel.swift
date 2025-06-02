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
    @Published var selectedPromptID: UUID?
    @Published var availableModels: [String] = []
    @Published var isLoadingModels: Bool = false
    @Published var temperature: Double = 0.7
    
    // Computed property to check if there's a service error
    var hasServiceError: Bool {
        return currentService == nil
    }
    
    // Method to update error message based on service status
    // This should be called outside of view rendering
    func updateErrorMessageIfNeeded() {
        if currentService == nil {
            if storage.savedEndpoints.isEmpty {
                // Only show error if there are no endpoints at all
                errorMessage = "No endpoints are configured"
            } else if let endpointID = selectedEndpoint,
                      let endpoint = storage.savedEndpoints.first(where: { $0.id == endpointID }),
                      endpoint.endpointType == .localModel && endpoint.url.isEmpty {
                // Show error for incomplete local model configuration
                errorMessage = "Local model file not selected"
            } else if let endpointID = selectedEndpoint,
                      let endpoint = storage.savedEndpoints.first(where: { $0.id == endpointID }),
                      endpoint.requiresAuth && storage.getToken(for: endpointID) == nil {
                // Show error for missing API token
                errorMessage = "API token required for this endpoint"
            } else if selectedEndpoint != nil {
                // Only show generic error if an endpoint is selected but service failed
                errorMessage = "Could not initialize chat service"
            } else {
                // Clear error message if no endpoint is selected (this is not an error state)
                errorMessage = nil
            }
        } else {
            // Clear error message when service is available
            errorMessage = nil
        }
    }
    
    private var storage: AppStorageManager
    private var currentTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    // Service for the current endpoint
    private var currentService: (any LLMServiceProtocol)?
    
    init(storage: AppStorageManager = .shared) {
        self.storage = storage
        
        // Try to initialize with the default endpoint
        if let defaultEndpointID = storage.defaultEndpointID {
            selectedEndpoint = defaultEndpointID
            
            // Initialize the service for this endpoint
            updateSelectedEndpoint(defaultEndpointID)
        } else if let firstEndpoint = storage.savedEndpoints.first {
            // If no default is set, use the first available endpoint
            selectedEndpoint = firstEndpoint.id
            updateSelectedEndpoint(firstEndpoint.id)
        }
        
        // Update error message based on current state
        updateErrorMessageIfNeeded()
        
        // Register for notifications when the default endpoint changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDefaultEndpointChanged),
            name: .defaultEndpointChanged,
            object: nil
        )
        
        // Register for notifications when an endpoint is updated
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEndpointUpdated),
            name: .endpointUpdated,
            object: nil
        )
        
        // Register for notifications when the default prompt changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDefaultPromptChanged),
            name: .defaultPromptChanged,
            object: nil
        )
        
        // Register for notifications when the language changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChanged),
            name: .languageChanged,
            object: nil
        )
        
        // Observe changes to the selected endpoint
        $selectedEndpoint
            .compactMap { $0 }
            .sink { [weak self] endpointID in
                self?.updateSelectedEndpoint(endpointID)
                self?.updateErrorMessageIfNeeded()
            }
            .store(in: &cancellables)
        if let defaultID = storage.defaultEndpointID {
            selectedEndpoint = defaultID
            
            // Try to create a service for the default endpoint
            if let endpoint = storage.savedEndpoints.first(where: { $0.id == defaultID }) {
                Task { @MainActor in
                    do {
                        let token = endpoint.requiresAuth ? storage.getToken(for: defaultID) : nil
                        currentService = try LLMServiceFactory.createService(endpoint: endpoint, apiToken: token)
                        
                        // Update available models
                        updateAvailableModels(for: endpoint)
                        
                        // Update the model selection to match the endpoint's default model
                        if !endpoint.defaultModel.isEmpty {
                            selectedModel = endpoint.defaultModel
                        }
                    } catch {
                        print("Failed to create service for default endpoint: \(error)")
                    }
                }
            }
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
                    // Check if there are any endpoints configured
                    if storage.savedEndpoints.isEmpty {
                        throw ChatError.noEndpointsConfigured
                    } else if selectedEndpoint == nil {
                        throw ChatError.noEndpointSelected
                    } else {
                        throw ChatError.noServiceAvailable
                    }
                }
                
                // Get history without the last empty message
                let history = Array(messages.dropLast())
                
                // Get system prompt and user prompt based on selection
                var systemPromptText = storage.systemPrompt
                var userPromptText = storage.userPrompt
                
                // If a specific prompt is selected for this chat, use it instead of the default
                if let promptID = selectedPromptID, 
                   let selectedPrompt = storage.savedPrompts.first(where: { $0.id == promptID }) {
                    systemPromptText = selectedPrompt.systemPrompt
                    userPromptText = selectedPrompt.userPrompt
                } else if let endpointID = selectedEndpoint,
                          let endpoint = storage.savedEndpoints.first(where: { $0.id == endpointID }),
                          let defaultPromptID = endpoint.defaultPromptID,
                          let defaultPrompt = storage.savedPrompts.first(where: { $0.id == defaultPromptID }) {
                    // If no chat-specific prompt is selected but the endpoint has a default prompt, use that
                    systemPromptText = defaultPrompt.systemPrompt
                    userPromptText = defaultPrompt.userPrompt
                }
                
                // Add language instruction if a specific language is selected
                if storage.preferredLanguage != .system, 
                   let languageInstruction = storage.preferredLanguage.promptInstruction {
                    systemPromptText += "\n\n" + languageInstruction
                }
                
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
            currentService = nil
            updateErrorMessageIfNeeded()
            return
        }
        
        do {
            // Create the appropriate service for this endpoint
            let token = endpoint.requiresAuth ? storage.getToken(for: endpointID) : nil
            currentService = try LLMServiceFactory.createService(endpoint: endpoint, apiToken: token)
            
            // Update available models
            updateAvailableModels(for: endpoint)
            
            // Update the model selection to match the endpoint's default model
            if !endpoint.defaultModel.isEmpty {
                selectedModel = endpoint.defaultModel
                print("Updated selected model to: \(endpoint.defaultModel) for endpoint: \(endpoint.name)")
            }
        } catch {
            print("Failed to create service for endpoint: \(error)")
            handleError(error)
            // Set currentService to nil to trigger the appropriate error message
            currentService = nil
            updateErrorMessageIfNeeded()
        }
    }
    
    @objc private func handleDefaultEndpointChanged(_ notification: Notification) {
        if let newDefaultID = notification.object as? UUID {
            // If we don't have a selected endpoint yet, use the new default
            if selectedEndpoint == nil {
                selectedEndpoint = newDefaultID
                print("ChatViewModel: Using new default endpoint")
            }
        }
    }
    
    @objc private func handleEndpointUpdated(_ notification: Notification) {
        if let updatedEndpoint = notification.object as? SavedEndpoint,
           let selectedID = selectedEndpoint,
           updatedEndpoint.id == selectedID {
            // If the currently selected endpoint was updated, refresh the available models
            print("ChatViewModel: Updating models for modified endpoint: \(updatedEndpoint.name)")
            
            // Update the service with the latest endpoint configuration
            updateSelectedEndpoint(selectedID)
            
            // Update available models based on the updated endpoint
            updateAvailableModels(for: updatedEndpoint)
            
            // If the endpoint has a default prompt, update the selected prompt
            if let promptID = updatedEndpoint.defaultPromptID {
                selectedPromptID = promptID
            }
        }
    }
    
    @objc private func handleDefaultPromptChanged(_ notification: Notification) {
        if let promptID = notification.object as? UUID {
            // Update the selected prompt ID
            selectedPromptID = promptID
            print("ChatViewModel: Updated selected prompt ID to \(promptID)")
        }
    }
    
    @objc private func handleLanguageChanged(_ notification: Notification) {
        // No need to store the language here as we'll get it directly from storage
        // when sending messages
        print("ChatViewModel: Language preference changed")
    }
    
    private func updateAvailableModels(for endpoint: SavedEndpoint) {
        // For local models, we only have the one model
        if endpoint.endpointType == .localModel {
            availableModels = [endpoint.defaultModel]
            selectedModel = endpoint.defaultModel
            return
        }
        
        // For custom APIs, use the stored available models
        if endpoint.endpointType == .customAPI && !endpoint.availableModels.isEmpty {
            availableModels = endpoint.availableModels
            // Set selected model to default or first available
            if endpoint.availableModels.contains(endpoint.defaultModel) {
                selectedModel = endpoint.defaultModel
            } else if !endpoint.availableModels.isEmpty {
                selectedModel = endpoint.availableModels[0]
            }
            return
        }
        
        // For OpenAI and other remote endpoints, fetch available models
        Task {
            do {
                isLoadingModels = true
                let models = try await currentService?.getAvailableModels() ?? []
                
                await MainActor.run {
                    // If we got models from the API, use those
                    if !models.isEmpty {
                        self.availableModels = models
                        self.selectedModel = models.contains(endpoint.defaultModel) ? endpoint.defaultModel : models[0]
                    } else {
                        // If no models returned but we have stored models, use those
                        if !endpoint.availableModels.isEmpty {
                            self.availableModels = endpoint.availableModels
                            self.selectedModel = endpoint.availableModels.contains(endpoint.defaultModel) ? 
                                endpoint.defaultModel : endpoint.availableModels[0]
                        } else {
                            // Fallback to just the default model
                            self.availableModels = [endpoint.defaultModel]
                            self.selectedModel = endpoint.defaultModel
                        }
                    }
                    self.isLoadingModels = false
                }
            } catch {
                await MainActor.run {
                    // If API call fails, fall back to stored models or default
                    if !endpoint.availableModels.isEmpty {
                        self.availableModels = endpoint.availableModels
                        self.selectedModel = endpoint.availableModels.contains(endpoint.defaultModel) ? 
                            endpoint.defaultModel : endpoint.availableModels[0]
                    } else {
                        self.availableModels = [endpoint.defaultModel]
                        self.selectedModel = endpoint.defaultModel
                    }
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
    case noEndpointsConfigured
    case noEndpointSelected
    case invalidEndpoint(String)
    case apiError(String)
    case unauthorized
    case invalidResponse
    case invalidModel
    
    var errorDescription: String? {
        switch self {
        case .noServiceAvailable:
            return "No chat service is available. Please configure an endpoint in settings."
        case .noEndpointsConfigured:
            return "No endpoints are configured. Please add an endpoint in settings."
        case .noEndpointSelected:
            return "No endpoint is selected. Please select an endpoint in settings."
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
