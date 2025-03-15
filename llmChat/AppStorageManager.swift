//
//  AppStorageManager.swift
//  llmChat
//
//  Created by Joshua Impson on 3/7/25.
//

import Foundation

// Model for saved prompts
struct SavedPrompt: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var systemPrompt: String
    var userPrompt: String
    
    // For backward compatibility
    var content: String {
        return systemPrompt
    }
    
    init(id: UUID = UUID(), name: String, systemPrompt: String, userPrompt: String = "") {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
    }
    
    // Backward compatibility initializer
    init(id: UUID = UUID(), name: String, content: String) {
        self.id = id
        self.name = name
        self.systemPrompt = content
        self.userPrompt = ""
    }
}

// Model for saved endpoints
struct SavedEndpoint: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var url: String
    var isChatEndpoint: Bool
    var requiresAuth: Bool
    var defaultModel: String
    var temperature: Double
    
    init(id: UUID = UUID(), name: String, url: String, isChatEndpoint: Bool, requiresAuth: Bool = true, defaultModel: String = "gpt-3.5-turbo", temperature: Double = 1.0) {
        self.id = id
        self.name = name
        self.url = url
        self.isChatEndpoint = isChatEndpoint
        self.requiresAuth = requiresAuth
        self.defaultModel = defaultModel
        self.temperature = temperature
    }
}

class AppStorageManager: ObservableObject {
    // Models available for the current endpoint
    @Published var availableModels: [String] = []
    @Published var hasValidEndpoint: Bool = false
    // Add a method to save endpoints to UserDefaults
    private func saveEndpoints() {
        if let encodedData = try? JSONEncoder().encode(savedEndpoints) {
            UserDefaults.standard.set(encodedData, forKey: "savedEndpoints")
        }
    }
    
    // Dictionary to store API tokens for each endpoint
    @Published var endpointTokens: [String: String] = {
        if let data = UserDefaults.standard.data(forKey: "endpointTokens"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            return decoded
        }
        return [:]
    }() {
        didSet {
            if let encoded = try? JSONEncoder().encode(endpointTokens) {
                UserDefaults.standard.set(encoded, forKey: "endpointTokens")
            }
        }
    }
    
    @Published var apiToken: String {
        didSet { UserDefaults.standard.set(apiToken, forKey: "apiToken") }
    }
    
    @Published var apiEndpoint: String {
        didSet { UserDefaults.standard.set(apiEndpoint, forKey: "apiEndpoint") }
    }
    
    @Published var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: "systemPrompt") }
    }
    
    @Published var userPrompt: String {
        didSet { UserDefaults.standard.set(userPrompt, forKey: "userPrompt") }
    }
    
    // For backward compatibility
    var prompt: String {
        get { return systemPrompt }
        set { systemPrompt = newValue }
    }
    
    @Published var savedPrompts: [SavedPrompt] = [] {
        didSet {
            if let encoded = try? JSONEncoder().encode(savedPrompts) {
                UserDefaults.standard.set(encoded, forKey: "savedPrompts")
            }
        }
    }
    
    @Published var savedEndpoints: [SavedEndpoint] = [] {
        didSet {
            if let encoded = try? JSONEncoder().encode(savedEndpoints) {
                UserDefaults.standard.set(encoded, forKey: "savedEndpoints")
            }
        }
    }
    
    @Published var defaultEndpointID: UUID? {
        didSet {
            if let id = defaultEndpointID {
                UserDefaults.standard.set(id.uuidString, forKey: "defaultEndpointID")
            } else {
                UserDefaults.standard.removeObject(forKey: "defaultEndpointID")
            }
        }
    }
    
    @Published var defaultPromptID: UUID? {
        didSet {
            if let id = defaultPromptID {
                UserDefaults.standard.set(id.uuidString, forKey: "defaultPromptID")
            } else {
                UserDefaults.standard.removeObject(forKey: "defaultPromptID")
            }
        }
    }
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

    init() {
        self.apiToken = UserDefaults.standard.string(forKey: "apiToken") ?? ""
        self.apiEndpoint = UserDefaults.standard.string(forKey: "apiEndpoint") ?? ""
        self.systemPrompt = UserDefaults.standard.string(forKey: "systemPrompt") ?? "You are a helpful AI assistant."
        self.userPrompt = UserDefaults.standard.string(forKey: "userPrompt") ?? ""
        self.temperature = UserDefaults.standard.double(forKey: "temperature") != 0 ? UserDefaults.standard.double(forKey: "temperature") : 1.0
        self.preferredLanguage = UserDefaults.standard.string(forKey: "preferredLanguage") ?? "English"
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
            let openAIEndpoint = SavedEndpoint(name: "OpenAI", url: "https://api.openai.com/v1/chat/completions", isChatEndpoint: true, requiresAuth: true, defaultModel: "gpt-3.5-turbo")
            let anthropicEndpoint = SavedEndpoint(name: "Anthropic", url: "https://api.anthropic.com/v1/messages", isChatEndpoint: true, requiresAuth: true, defaultModel: "claude-3-opus-20240229")
            
            self.savedEndpoints = [openAIEndpoint, anthropicEndpoint]
            
            // Set OpenAI as the default endpoint if no default is set
            if self.defaultEndpointID == nil {
                self.defaultEndpointID = openAIEndpoint.id
            }
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
    
    // MARK: - Endpoint Validation
    
    func checkEndpointAndFetchModels(completion: @escaping (Bool) -> Void) {
        guard !apiEndpoint.isEmpty else {
            hasValidEndpoint = false
            availableModels = []
            completion(false)
            return
        }
        
        // Extract the base URL from the endpoint URL
        var baseURL = apiEndpoint
        
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
    
    func addPrompt(name: String, systemPrompt: String, userPrompt: String = "") {
        let newPrompt = SavedPrompt(name: name, systemPrompt: systemPrompt, userPrompt: userPrompt)
        savedPrompts.append(newPrompt)
    }
    
    // Backward compatibility method
    func addPrompt(name: String, content: String) {
        let newPrompt = SavedPrompt(name: name, systemPrompt: content)
        savedPrompts.append(newPrompt)
    }
    
    func updatePrompt(id: UUID, name: String, systemPrompt: String, userPrompt: String = "") {
        if let index = savedPrompts.firstIndex(where: { $0.id == id }) {
            savedPrompts[index] = SavedPrompt(id: id, name: name, systemPrompt: systemPrompt, userPrompt: userPrompt)
        }
    }
    
    // Backward compatibility method
    func updatePrompt(id: UUID, name: String, content: String) {
        if let index = savedPrompts.firstIndex(where: { $0.id == id }) {
            // Preserve the existing userPrompt if there is one
            let existingUserPrompt = savedPrompts[index].userPrompt
            savedPrompts[index] = SavedPrompt(id: id, name: name, systemPrompt: content, userPrompt: existingUserPrompt)
        }
    }
    
    func deletePrompt(at indexSet: IndexSet) {
        savedPrompts.remove(atOffsets: indexSet)
    }
    
    func selectPrompt(id: UUID) {
        if let selectedPrompt = savedPrompts.first(where: { $0.id == id }) {
            systemPrompt = selectedPrompt.systemPrompt
            userPrompt = selectedPrompt.userPrompt
        }
    }
    
    func setDefaultPrompt(id: UUID) {
        if savedPrompts.contains(where: { $0.id == id }) {
            defaultPromptID = id
            objectWillChange.send()
        }
    }
    
    // MARK: - Endpoint Management
    
    @discardableResult
    func addEndpoint(name: String, url: String, isChatEndpoint: Bool, requiresAuth: Bool, defaultModel: String, temperature: Double = 1.0) -> UUID {
        let newEndpoint = SavedEndpoint(name: name, url: url, isChatEndpoint: isChatEndpoint, requiresAuth: requiresAuth, defaultModel: defaultModel, temperature: temperature)
        savedEndpoints.append(newEndpoint)
        saveEndpoints()
        // Notify observers that endpoints have changed
        objectWillChange.send()
        return newEndpoint.id
    }
    
    func updateEndpoint(id: UUID, name: String, url: String, isChatEndpoint: Bool, requiresAuth: Bool, defaultModel: String, temperature: Double) {
        if let index = savedEndpoints.firstIndex(where: { $0.id == id }) {
            savedEndpoints[index] = SavedEndpoint(id: id, name: name, url: url, isChatEndpoint: isChatEndpoint, requiresAuth: requiresAuth, defaultModel: defaultModel, temperature: temperature)
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
    
    func selectEndpoint(id: UUID) {
        if let selectedEndpoint = savedEndpoints.first(where: { $0.id == id }) {
            // Simply use the URL as stored
            apiEndpoint = selectedEndpoint.url
            useChatEndpoint = selectedEndpoint.isChatEndpoint
            preferredModel = selectedEndpoint.defaultModel
            temperature = selectedEndpoint.temperature
            
            // Set the API token for this endpoint if it exists and requires auth
            if selectedEndpoint.requiresAuth {
                let storedToken = endpointTokens[id.uuidString] ?? ""
                apiToken = storedToken
                
                // Debug logging
                if !storedToken.isEmpty {
                    print("Retrieved API token for endpoint \(selectedEndpoint.name): \(storedToken.prefix(5))...\(storedToken.suffix(5))")
                } else {
                    print("No API token found for endpoint \(selectedEndpoint.name)")
                }
            } else {
                // Clear the API token if the endpoint doesn't require auth
                apiToken = ""
                print("Cleared API token for endpoint \(selectedEndpoint.name) as it doesn't require auth")
            }
            
            // Ensure the changes are immediately applied
            UserDefaults.standard.set(apiEndpoint, forKey: "apiEndpoint")
            UserDefaults.standard.set(useChatEndpoint, forKey: "useChatEndpoint")
            UserDefaults.standard.set(preferredModel, forKey: "preferredModel")
            UserDefaults.standard.set(temperature, forKey: "temperature")
            UserDefaults.standard.set(apiToken, forKey: "apiToken")
            
            // Notify observers that the endpoint has changed
            objectWillChange.send()
        }
    }
    
    func setDefaultEndpoint(id: UUID) {
        if savedEndpoints.contains(where: { $0.id == id }) {
            defaultEndpointID = id
            UserDefaults.standard.set(id.uuidString, forKey: "defaultEndpointID")
            // Notify observers that the default endpoint has changed
            objectWillChange.send()
        }
    }
    
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
