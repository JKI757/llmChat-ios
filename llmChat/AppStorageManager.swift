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
    var content: String
    
    init(id: UUID = UUID(), name: String, content: String) {
        self.id = id
        self.name = name
        self.content = content
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
    
    init(id: UUID = UUID(), name: String, url: String, isChatEndpoint: Bool, requiresAuth: Bool = true, defaultModel: String = "gpt-3.5-turbo") {
        self.id = id
        self.name = name
        self.url = url
        self.isChatEndpoint = isChatEndpoint
        self.requiresAuth = requiresAuth
        self.defaultModel = defaultModel
    }
}

class AppStorageManager: ObservableObject {
    @Published var apiToken: String {
        didSet { UserDefaults.standard.set(apiToken, forKey: "apiToken") }
    }
    
    @Published var apiEndpoint: String {
        didSet { UserDefaults.standard.set(apiEndpoint, forKey: "apiEndpoint") }
    }
    
    @Published var prompt: String {
        didSet { UserDefaults.standard.set(prompt, forKey: "prompt") }
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
    @Published var preferredLanguage: String {
        didSet { UserDefaults.standard.set(preferredLanguage, forKey: "preferredLanguage") }
    }
    @Published var preferredModel: String {
        didSet { UserDefaults.standard.set(preferredModel, forKey: "preferredModel") }
    }
    @Published var useChatEndpoint: Bool {
        didSet { UserDefaults.standard.set(useChatEndpoint, forKey: "useChatEndpoint") }
    }

    init() {
        self.apiToken = UserDefaults.standard.string(forKey: "apiToken") ?? ""
        self.apiEndpoint = UserDefaults.standard.string(forKey: "apiEndpoint") ?? ""
        self.prompt = UserDefaults.standard.string(forKey: "prompt") ?? "You are a helpful AI assistant."
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
                SavedPrompt(name: "Default Assistant", content: "You are a helpful AI assistant."),
                SavedPrompt(name: "Code Expert", content: "You are a coding expert who provides clear, efficient solutions with explanations.")
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
    }
    
    // MARK: - Prompt Management
    
    func addPrompt(name: String, content: String) {
        let newPrompt = SavedPrompt(name: name, content: content)
        savedPrompts.append(newPrompt)
    }
    
    func updatePrompt(id: UUID, name: String, content: String) {
        if let index = savedPrompts.firstIndex(where: { $0.id == id }) {
            savedPrompts[index] = SavedPrompt(id: id, name: name, content: content)
        }
    }
    
    func deletePrompt(at indexSet: IndexSet) {
        savedPrompts.remove(atOffsets: indexSet)
    }
    
    func selectPrompt(id: UUID) {
        if let selectedPrompt = savedPrompts.first(where: { $0.id == id }) {
            prompt = selectedPrompt.content
        }
    }
    
    // MARK: - Endpoint Management
    
    @discardableResult
    func addEndpoint(name: String, url: String, isChatEndpoint: Bool, requiresAuth: Bool, defaultModel: String) -> UUID {
        let newEndpoint = SavedEndpoint(name: name, url: url, isChatEndpoint: isChatEndpoint, requiresAuth: requiresAuth, defaultModel: defaultModel)
        savedEndpoints.append(newEndpoint)
        return newEndpoint.id
    }
    
    func updateEndpoint(id: UUID, name: String, url: String, isChatEndpoint: Bool, requiresAuth: Bool, defaultModel: String) {
        if let index = savedEndpoints.firstIndex(where: { $0.id == id }) {
            savedEndpoints[index] = SavedEndpoint(id: id, name: name, url: url, isChatEndpoint: isChatEndpoint, requiresAuth: requiresAuth, defaultModel: defaultModel)
        }
    }
    
    func deleteEndpoint(at indexSet: IndexSet) {
        savedEndpoints.remove(atOffsets: indexSet)
    }
    
    func selectEndpoint(id: UUID) {
        if let selectedEndpoint = savedEndpoints.first(where: { $0.id == id }) {
            // Simply use the URL as stored
            apiEndpoint = selectedEndpoint.url
            useChatEndpoint = selectedEndpoint.isChatEndpoint
            preferredModel = selectedEndpoint.defaultModel
            
            // Ensure the changes are immediately applied
            UserDefaults.standard.set(apiEndpoint, forKey: "apiEndpoint")
            UserDefaults.standard.set(useChatEndpoint, forKey: "useChatEndpoint")
            UserDefaults.standard.set(preferredModel, forKey: "preferredModel")
            
            // Notify observers that the endpoint has changed
            objectWillChange.send()
        }
    }
    
    func setDefaultEndpoint(id: UUID) {
        if savedEndpoints.contains(where: { $0.id == id }) {
            defaultEndpointID = id
        }
    }
    
    func moveEndpoint(from source: IndexSet, to destination: Int) {
        savedEndpoints.move(fromOffsets: source, toOffset: destination)
    }
}
