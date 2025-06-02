//
//  AppStorageManager.swift
//  llmChat
//
//  Created by Joshua Impson on 3/7/25.
//

import Foundation
import CoreData

// MARK: - Saved Prompt Model

/// Model for saved prompts with support for both system and user prompts
struct SavedPrompt: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var systemPrompt: String
    var userPrompt: String
    var lastUsed: Date?
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        systemPrompt: String,
        userPrompt: String = "",
        lastUsed: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.lastUsed = lastUsed
        self.createdAt = createdAt
    }
    
    /// Updates the last used timestamp to now
    func withUpdatedLastUsed() -> SavedPrompt {
        var updated = self
        updated.lastUsed = Date()
        return updated
    }
}

// Using SavedEndpoint from Models/SavedEndpoint.swift

// MARK: - App Storage Manager Protocol

/// Protocol for app storage management to facilitate testing
protocol AppStorageManagerProtocol {
    var defaultEndpointID: UUID? { get }
    var savedEndpoints: [SavedEndpoint] { get }
    
    func getToken(for endpointID: UUID) -> String?
    func getEndpoint(by id: UUID) -> SavedEndpoint?
}

// MARK: - Core Data Manager

class AppStorageManager: ObservableObject, AppStorageManagerProtocol {
    // Singleton instance
    static let shared: AppStorageManager = {
        let instance = AppStorageManager()
        return instance
    }()
    
    // Core Data Manager
    let coreDataManager = CoreDataManager.shared
    
    // MARK: - Published Properties
    
    @Published var systemPrompt: String = "You are a helpful AI assistant." {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: "systemPrompt") }
    }
    
    @Published var userPrompt: String = "" {
        didSet { UserDefaults.standard.set(userPrompt, forKey: "userPrompt") }
    }
    
    @Published var savedPrompts: [SavedPrompt] = [] {
        didSet {
            if let encoded = try? JSONEncoder().encode(savedPrompts) {
                UserDefaults.standard.set(encoded, forKey: "savedPrompts")
            }
        }
    }
    
    @Published var savedEndpoints: [SavedEndpoint] = []
    @Published var defaultEndpointID: UUID?
    @Published var defaultPromptID: UUID?
    @Published var hasValidEndpoint: Bool = false
    @Published var availableModels: [String] = []
    @Published var selectedModel: String = ""
    private var endpointTokens: [String: String] = [:]
    
    // MARK: - Initialization
    
    init() {
        // Initialize properties with default values
        self.apiToken = UserDefaults.standard.string(forKey: "apiToken") ?? ""
        self.apiEndpoint = UserDefaults.standard.string(forKey: "apiEndpoint") ?? "https://api.openai.com/v1"
        self.preferredLanguage = UserDefaults.standard.string(forKey: "preferredLanguage") ?? "en"
        self.preferredModel = UserDefaults.standard.string(forKey: "preferredModel") ?? "gpt-3.5-turbo"
        self.useChatEndpoint = UserDefaults.standard.bool(forKey: "useChatEndpoint")
        self.temperature = UserDefaults.standard.double(forKey: "temperature")
        if self.temperature == 0 { self.temperature = 0.7 } // Default if not set
        
        // Load saved prompts
        if let data = UserDefaults.standard.data(forKey: "savedPrompts"),
           let prompts = try? JSONDecoder().decode([SavedPrompt].self, from: data) {
            self.savedPrompts = prompts
        } else {
            // Create a default prompt if none exist
            self.savedPrompts = [
                SavedPrompt(
                    name: "Default Assistant",
                    systemPrompt: "You are a helpful AI assistant.",
                    userPrompt: ""
                )
            ]
        }
        
        // Load saved endpoints
        if let data = UserDefaults.standard.data(forKey: "savedEndpoints"),
           let endpoints = try? JSONDecoder().decode([SavedEndpoint].self, from: data) {
            self.savedEndpoints = endpoints
        } else {
            self.savedEndpoints = [SavedEndpoint.defaultOpenAI]
        }
        
        // Load endpoint tokens
        if let data = UserDefaults.standard.data(forKey: "endpointTokens"),
           let tokens = try? JSONDecoder().decode([String: String].self, from: data) {
            self.endpointTokens = tokens
        }
        
        // Load other settings
        self.systemPrompt = UserDefaults.standard.string(forKey: "systemPrompt") ?? "You are a helpful AI assistant."
        self.userPrompt = UserDefaults.standard.string(forKey: "userPrompt") ?? ""
        self.defaultEndpointID = UUID(uuidString: UserDefaults.standard.string(forKey: "defaultEndpointID") ?? "")
        self.defaultPromptID = UUID(uuidString: UserDefaults.standard.string(forKey: "defaultPromptID") ?? "")
    }
    
    // MARK: - Token Management
    
    func getToken(for endpointID: UUID) -> String? {
        return endpointTokens[endpointID.uuidString]
    }
    
    func getEndpoint(by id: UUID) -> SavedEndpoint? {
        return savedEndpoints.first(where: { $0.id == id })
    }
    
    func setToken(_ token: String, for endpointID: UUID) {
        endpointTokens[endpointID.uuidString] = token
        saveEndpointTokens()
    }
    
    // MARK: - Saving Methods
    
    private func savePrompts() {
        if let data = try? JSONEncoder().encode(savedPrompts) {
            UserDefaults.standard.set(data, forKey: "savedPrompts")
        }
    }
    
    private func saveEndpoints() {
        if let data = try? JSONEncoder().encode(savedEndpoints) {
            UserDefaults.standard.set(data, forKey: "savedEndpoints")
        }
    }
    
    private func saveEndpointTokens() {
        if let data = try? JSONEncoder().encode(endpointTokens) {
            UserDefaults.standard.set(data, forKey: "endpointTokens")
        }
    }
    
    // MARK: - Endpoint Management
    
    func addEndpoint(_ endpoint: SavedEndpoint) {
        savedEndpoints.append(endpoint)
        saveEndpoints()
    }
    
    func updateEndpoint(_ endpoint: SavedEndpoint) {
        if let index = savedEndpoints.firstIndex(where: { $0.id == endpoint.id }) {
            savedEndpoints[index] = endpoint
            saveEndpoints()
        }
    }
    
    func deleteEndpoint(_ endpoint: SavedEndpoint) {
        savedEndpoints.removeAll { $0.id == endpoint.id }
        endpointTokens.removeValue(forKey: endpoint.id.uuidString)
        saveEndpoints()
        saveEndpointTokens()
    }
    
    func setDefaultEndpoint(id: UUID) {
        if savedEndpoints.contains(where: { $0.id == id }) {
            defaultEndpointID = id
            UserDefaults.standard.set(id.uuidString, forKey: "defaultEndpointID")
            // Notify observers that the default endpoint has changed
            objectWillChange.send()
        }
    }
    
    // MARK: - Prompt Management
    
    // First declaration of addPrompt is kept
    
    func updatePrompt(_ prompt: SavedPrompt) {
        if let index = savedPrompts.firstIndex(where: { $0.id == prompt.id }) {
            savedPrompts[index] = prompt
            savePrompts()
        }
    }
    
    func deletePrompt(_ prompt: SavedPrompt) {
        savedPrompts.removeAll { $0.id == prompt.id }
        savePrompts()
    }
    
    func selectPrompt(id: UUID) {
        if let prompt = savedPrompts.first(where: { $0.id == id }) {
            self.systemPrompt = prompt.systemPrompt
            self.userPrompt = prompt.userPrompt
            UserDefaults.standard.set(prompt.systemPrompt, forKey: "systemPrompt")
            UserDefaults.standard.set(prompt.userPrompt, forKey: "userPrompt")
            
            // Update last used timestamp
            updatePrompt(prompt.withUpdatedLastUsed())
        }
    }
    
    func setDefaultPrompt(id: UUID) {
        if savedPrompts.contains(where: { $0.id == id }) {
            defaultPromptID = id
            UserDefaults.standard.set(id.uuidString, forKey: "defaultPromptID")
        }
    }
    
    // Models that don't support system prompts
    @Published var modelsWithoutSystemPrompt: [String] = ["o1", "o1-mini", "o1-preview"]
    
    // Centralized list of supported languages
    static let supportedLanguages = ["English", "Spanish", "French", "German", "Mandarin", "Japanese", "Business Japanese", "Tagalog", "Taglish", "Korean", "Russian"]
    
    // Check if the current model supports system prompts
    var currentModelSupportsSystemPrompt: Bool {
        // Check if the preferred model contains any of the model names that don't support system prompts
        return !modelsWithoutSystemPrompt.contains { modelPrefix in
            preferredModel.contains(modelPrefix)
        }
    }
    
    // MARK: - Endpoint Management
    
    @Published var apiToken: String {
        didSet { UserDefaults.standard.set(apiToken, forKey: "apiToken") }
    }
    
    @Published var apiEndpoint: String {
        didSet { UserDefaults.standard.set(apiEndpoint, forKey: "apiEndpoint") }
    }
    
    // For backward compatibility
    var prompt: String {
        get { return systemPrompt }
        set { systemPrompt = newValue }
    }
    
    // Properties are already declared above
    @Published var preferredLanguage: String {
        didSet { UserDefaults.standard.set(preferredLanguage, forKey: "preferredLanguage") }
    }
    @Published var preferredModel: String {
        didSet { UserDefaults.standard.set(preferredModel, forKey: "preferredModel") }
    }
    @Published var useChatEndpoint: Bool {
        didSet { UserDefaults.standard.set(useChatEndpoint, forKey: "useChatEndpoint") }
    }
    
    @Published var temperature: Double {
        didSet { UserDefaults.standard.set(temperature, forKey: "temperature") }
    }

    // MARK: - Model Loading
    
    func loadInitialModels() {
        // Load initial models
        if let endpointID = defaultEndpointID {
            checkEndpointAndFetchModels(endpointID: endpointID) { _ in }
        }
        self.preferredModel = UserDefaults.standard.string(forKey: "preferredModel") ?? "gpt-3.5-turbo"
        self.useChatEndpoint = UserDefaults.standard.bool(forKey: "useChatEndpoint")
        
        // Load default endpoint ID
        if let defaultIDString = UserDefaults.standard.string(forKey: "defaultEndpointID"),
           let uuid = UUID(uuidString: defaultIDString) {
            self.defaultEndpointID = uuid
        } else {
            self.defaultEndpointID = nil
        }
        
        // Load saved prompts
        if let savedPromptsData = UserDefaults.standard.data(forKey: "savedPrompts"),
           let decodedPrompts = try? JSONDecoder().decode([SavedPrompt].self, from: savedPromptsData) {
            self.savedPrompts = decodedPrompts
        } else {
            // Add default prompts if none exist
            self.savedPrompts = [
                SavedPrompt(name: "Default Assistant", systemPrompt: "You are a helpful AI assistant.", userPrompt: ""),
                SavedPrompt(name: "Code Expert", systemPrompt: "You are a coding expert who provides clear, efficient solutions with explanations.", userPrompt: "Please help me solve the following coding problem:")
            ]
        }
        
        // Load saved endpoints
        if let savedEndpointsData = UserDefaults.standard.data(forKey: "savedEndpoints"),
           let decodedEndpoints = try? JSONDecoder().decode([SavedEndpoint].self, from: savedEndpointsData) {
            self.savedEndpoints = decodedEndpoints
        } else {
            // Add default endpoints if none exist
        }
        
        // If we have a default endpoint, use it on startup
        if let defaultID = self.defaultEndpointID,
           let defaultEndpoint = self.savedEndpoints.first(where: { $0.id == defaultID }) {
            self.selectEndpoint(id: defaultID)
        }
        
        // Load default prompt ID
        if let defaultPromptIDString = UserDefaults.standard.string(forKey: "defaultPromptID"),
           let uuid = UUID(uuidString: defaultPromptIDString) {
            self.defaultPromptID = uuid
            
            // If we have a default prompt, use it on startup
            if let defaultPrompt = self.savedPrompts.first(where: { $0.id == uuid }) {
                self.selectPrompt(id: uuid)
            }
        } else if !self.savedPrompts.isEmpty {
            // Set the first prompt as default if none is set
            self.defaultPromptID = self.savedPrompts.first?.id
        }
    }
    
    /// Initializes default endpoints if none exist
    func initializeDefaultEndpoints() {
        guard savedEndpoints.isEmpty else { return }
        
        let openAIEndpoint = SavedEndpoint(
            name: "OpenAI",
            url: "https://api.openai.com",
            defaultModel: "gpt-3.5-turbo",
            requiresAuth: true,
            endpointType: .openAI,
            isChatEndpoint: true
        )
        
        let localModelEndpoint = SavedEndpoint(
            name: "Local Model",
            url: "",
            defaultModel: "local-model",
            requiresAuth: false,
            endpointType: .localModel,
            isChatEndpoint: true
        )
        
        savedEndpoints = [openAIEndpoint, localModelEndpoint]
        defaultEndpointID = openAIEndpoint.id
    }
    
    // MARK: - Endpoint Validation
    
    /// Checks if an endpoint is valid and fetches available models
    /// - Parameters:
    ///   - endpointID: Optional endpoint ID to check (uses selected endpoint if nil)
    ///   - completion: Completion handler with success status
    func checkEndpointAndFetchModels(endpointID: UUID? = nil, completion: @escaping (Bool) -> Void) {
        let endpointID = endpointID ?? defaultEndpointID
        
        guard let endpoint = savedEndpoints.first(where: { $0.id == endpointID }) else {
            hasValidEndpoint = false
            availableModels = []
            completion(false)
            return
        }
        
        // Handle local models
        if endpoint.isLocalModel {
            hasValidEndpoint = true
            availableModels = [endpoint.defaultModel]
            completion(true)
            return
        }
        
        // Handle remote endpoints
        guard !endpoint.url.isEmpty else {
            hasValidEndpoint = false
            availableModels = []
            completion(false)
            return
        }
        
        // Extract the base URL from the endpoint URL
        var baseURL = endpoint.url
        
        // Clean the base URL - remove any path components after /v1/
        if baseURL.contains("/v1/") {
            if let range = baseURL.range(of: "/v1/") {
                baseURL = String(baseURL[..<range.lowerBound])
            }
        }
        
        // Remove trailing slashes
        while baseURL.hasSuffix("/") {
            baseURL = String(baseURL.dropLast())
        }
        
        // Construct the models URL
        let modelsURL = baseURL + "/v1/models"
        print("Fetching models from: \(modelsURL)")
        
        // Create URL request
        guard let url = URL(string: modelsURL) else {
            hasValidEndpoint = false
            availableModels = []
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30.0
        
        // Add authorization header if needed
        if !apiToken.isEmpty {
            let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    print("Error fetching models: \(error.localizedDescription)")
                    self.hasValidEndpoint = false
                    self.availableModels = []
                    completion(false)
                    return
                }
                
                guard let data = data else {
                    print("No data received when fetching models")
                    self.hasValidEndpoint = false
                    self.availableModels = []
                    completion(false)
                    return
                }
                
                // Try to parse the response
                do {
                    var models: [String] = []
                    
                    // First try OpenAI format
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let dataArray = json["data"] as? [[String: Any]] {
                        // OpenAI format
                        for item in dataArray {
                            if let id = item["id"] as? String {
                                models.append(id)
                            }
                        }
                    }
                    // Try Anthropic format
                    else if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                            let modelsArray = json["models"] as? [[String: Any]] {
                        for model in modelsArray {
                            if let name = model["name"] as? String {
                                models.append(name)
                            }
                        }
                    }
                    // Try simple array format
                    else if let modelsArray = try JSONSerialization.jsonObject(with: data) as? [String] {
                        models = modelsArray
                    }
                    
                    if !models.isEmpty {
                        self.availableModels = models
                        self.hasValidEndpoint = true
                        
                        // If the current model isn't in the list, select the first available model
                        if !models.contains(self.preferredModel) && !models.isEmpty {
                            self.preferredModel = models[0]
                        }
                        
                        completion(true)
                    } else {
                        print("No models found in response")
                        self.hasValidEndpoint = false
                        self.availableModels = []
                        completion(false)
                    }
                } catch {
                    print("Error parsing models response: \(error.localizedDescription)")
                    self.hasValidEndpoint = false
                    self.availableModels = []
                    completion(false)
                }
            }
        }.resume()
    }
    
    // MARK: - Prompt Management
    
    // Main addPrompt method with support for both system and user prompts
    func addPrompt(name: String, systemPrompt: String, userPrompt: String = "") {
        let newPrompt = SavedPrompt(name: name, systemPrompt: systemPrompt, userPrompt: userPrompt)
        savedPrompts.append(newPrompt)
        savePrompts()
    }
    
    // Backward compatibility method
    func addPrompt(name: String, content: String, role: String = "system") {
        // Convert old format to new format
        if role == "system" {
            addPrompt(name: name, systemPrompt: content, userPrompt: "")
        } else {
            addPrompt(name: name, systemPrompt: "", userPrompt: content)
        }
    }
    
    // Backward compatibility method - converts to new SavedPrompt format
    func updatePrompt(id: UUID, name: String, content: String, role: String = "system") {
        if let index = savedPrompts.firstIndex(where: { $0.id == id }) {
            let systemPrompt = role == "system" ? content : savedPrompts[index].systemPrompt
            let userPrompt = role == "user" ? content : savedPrompts[index].userPrompt
            
            let updatedPrompt = SavedPrompt(
                id: id,
                name: name,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                lastUsed: savedPrompts[index].lastUsed,
                createdAt: savedPrompts[index].createdAt
            )
            
            updatePrompt(updatedPrompt)
        }
    }
    
    // Backward compatibility method
    func updatePrompt(id: UUID, name: String, content: String) {
        // Call the more comprehensive method with system role as default
        updatePrompt(id: id, name: name, content: content, role: "system")
    }
    
    // New method to update both system and user prompts
    func updatePrompt(id: UUID, name: String, systemPrompt: String, userPrompt: String) {
        if let index = savedPrompts.firstIndex(where: { $0.id == id }) {
            let updatedPrompt = SavedPrompt(
                id: id,
                name: name,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                lastUsed: savedPrompts[index].lastUsed,
                createdAt: savedPrompts[index].createdAt
            )
            
            updatePrompt(updatedPrompt)
        }
    }
    
    func deletePrompt(at indexSet: IndexSet) {
        savedPrompts.remove(atOffsets: indexSet)
        savePrompts()
    }
    
    // Duplicate selectPrompt method removed - using the first implementation above
    
    // Duplicate setDefaultPrompt method removed - using the first implementation above
    
    // MARK: - Endpoint Management
    
    /// Adds a new endpoint
    /// - Parameters:
    ///   - name: Display name of the endpoint
    ///   - url: URL or local path for the endpoint
    ///   - endpointType: Type of the endpoint
    ///   - isChatEndpoint: Whether it's a chat endpoint
    ///   - requiresAuth: Whether authentication is required
    ///   - defaultModel: Default model to use
    ///   - temperature: Default temperature setting
    ///   - organizationID: Optional organization ID
    ///   - maxTokens: Maximum tokens for local models
    /// - Returns: The created endpoint
    @discardableResult
    func addEndpoint(
        name: String,
        url: String,
        endpointType: EndpointType = .openAI,
        isChatEndpoint: Bool = true,
        requiresAuth: Bool = true,
        defaultModel: String = "gpt-3.5-turbo",
        temperature: Double = 1.0,
        organizationID: String? = nil,
        maxTokens: Int? = 2048
    ) -> SavedEndpoint {
        let newEndpoint = SavedEndpoint(
            name: name,
            url: url,
            defaultModel: defaultModel,
            maxTokens: maxTokens,
            requiresAuth: requiresAuth,
            organizationID: organizationID,
            endpointType: endpointType,
            isChatEndpoint: isChatEndpoint,
            temperature: temperature
        )
        
        savedEndpoints.append(newEndpoint)
        
        // If this is the first endpoint, set it as default
        if savedEndpoints.count == 1 {
            defaultEndpointID = newEndpoint.id
        }
        
        return newEndpoint
    }
    
    func updateEndpoint(id: UUID, name: String, url: String, isChatEndpoint: Bool, requiresAuth: Bool, defaultModel: String, temperature: Double) {
        if let index = savedEndpoints.firstIndex(where: { $0.id == id }) {
            savedEndpoints[index] = SavedEndpoint(
                id: id,
                name: name,
                url: url,
                defaultModel: defaultModel,
                requiresAuth: requiresAuth,
                endpointType: savedEndpoints[index].endpointType,
                isChatEndpoint: isChatEndpoint,
                temperature: temperature
            )
            saveEndpoints()
            // Notify observers that endpoints have changed
            objectWillChange.send()
        }
    }
    
    func deleteEndpoint(at indexSet: IndexSet) {
        savedEndpoints.remove(atOffsets: indexSet)
        saveEndpoints()
        // Notify observers that endpoints have changed
        objectWillChange.send()
    }
    
    /// Selects an endpoint to use
    /// - Parameter id: ID of the endpoint to select
    /// - Returns: True if the endpoint was found and selected
    @discardableResult
    func selectEndpoint(id: UUID) -> Bool {
        guard savedEndpoints.contains(where: { $0.id == id }) else {
            return false
        }
        
        defaultEndpointID = id
        return true
    }
    
    // Duplicate setDefaultEndpoint method removed - using the first implementation above
    
    func moveEndpoint(from source: IndexSet, to destination: Int) {
        savedEndpoints.move(fromOffsets: source, toOffset: destination)
        saveEndpoints()
        // Notify observers that endpoints have changed
        objectWillChange.send()
    }
    
    // Save API token for a specific endpoint
    func saveAPIToken(for endpointID: UUID, token: String) {
        // Store the token in the endpoint tokens dictionary
        endpointTokens[endpointID.uuidString] = token
        
        // If this is the currently selected endpoint, also update the current token
        if let selectedEndpoint = savedEndpoints.first(where: { $0.id == endpointID }),
           selectedEndpoint.url == apiEndpoint {
            apiToken = token
            // Ensure the token is saved to UserDefaults
            UserDefaults.standard.set(token, forKey: "apiToken")
            print("Updated current API token: \(token.prefix(5))...\(token.suffix(5))")
        }
        
        // Ensure the changes are immediately applied
        if let encoded = try? JSONEncoder().encode(endpointTokens) {
            UserDefaults.standard.set(encoded, forKey: "endpointTokens")
        }
        
        // Notify observers that the token has changed
        objectWillChange.send()
    }
}
