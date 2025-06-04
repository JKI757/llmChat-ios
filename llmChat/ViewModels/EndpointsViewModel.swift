import Foundation
import SwiftUI

@MainActor
class EndpointsViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var showingError = false
    @Published var showingAddEndpoint = false
    @Published var editingEndpoint: SavedEndpoint?
    
    private let storage: AppStorageManager
    
    init(storage: AppStorageManager) {
        self.storage = storage
    }
    
    var endpoints: [SavedEndpoint] {
        // Access the endpoints through the storage manager
        let savedEndpoints = storage.savedEndpoints
        return savedEndpoints.sorted { $0.name < $1.name }
    }
    
    var savedPrompts: [SavedPrompt] {
        // Access the prompts through the storage manager
        return storage.savedPrompts
    }
    
    var defaultEndpointID: UUID? {
        // Access the default endpoint ID through the storage manager
        let defaultID = storage.defaultEndpointID
        return defaultID
    }
    
    func setDefaultEndpoint(_ endpoint: SavedEndpoint) {
        storage.defaultEndpointID = endpoint.id
    }
    
    func deleteEndpoints(at offsets: IndexSet) {
        storage.deleteEndpoint(at: offsets)
    }
    
    func editEndpoint(_ endpoint: SavedEndpoint) {
        editingEndpoint = endpoint
    }
    
    func refreshEndpoints() async {
        // This can be used to refresh models or other data
    }
    
    func getToken(for endpointID: UUID) -> String {
        storage.getToken(for: endpointID) ?? ""
    }
    
    func setToken(_ token: String, for endpointID: UUID) {
        storage.setToken(token, for: endpointID)
    }
    
    func saveEndpoint(_ endpoint: SavedEndpoint, token: String?) {
        // Get the current endpoints list
        let currentEndpoints = storage.savedEndpoints
        
        if let editingEndpoint = editingEndpoint, currentEndpoints.contains(where: { $0.id == editingEndpoint.id }) {
            // Update existing endpoint
            storage.updateEndpoint(endpoint)
            if let token = token, !token.isEmpty {
                setToken(token, for: endpoint.id)
            }
        } else {
            // Add new endpoint
            storage.addEndpoint(endpoint)
            if let token = token, !token.isEmpty {
                setToken(token, for: endpoint.id)
            }
            // If this is the first endpoint, set it as default
            if currentEndpoints.isEmpty {
                storage.setDefaultEndpoint(id: endpoint.id)
            }
        }
        // Notify that an endpoint has been updated
        NotificationCenter.default.post(name: .endpointUpdated, object: nil, userInfo: ["endpointID": endpoint.id])
        print("EndpointsViewModel: Posted .endpointUpdated notification for ID \(endpoint.id)")
    }
    
    func importLocalModel(from url: URL, modelName: String) async throws -> SavedEndpoint {
        // Create a new local model endpoint
        let endpoint = SavedEndpoint(
            name: modelName,
            url: url.path,
            defaultModel: modelName,
            maxTokens: 2048,
            requiresAuth: false,
            endpointType: .localModel,
            isChatEndpoint: true,
            temperature: 0.7
        )
        
        // Add the endpoint to storage
        storage.addEndpoint(endpoint)
        
        return endpoint
    }
    
    // MARK: - Model Fetching
    
    public func fetchOpenAIModels(baseURL: String, apiToken: String?, organizationID: String?) async throws -> [String] {
        guard var urlComponents = URLComponents(string: baseURL) else {
            throw NSError(domain: "EndpointsViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid base URL"])
        }
        
        // Append /models to the base URL's path.
        // User is expected to include /v1 in the base URL if required by the endpoint.
        var path = urlComponents.path
        if path.hasSuffix("/") {
            path.removeLast() // Avoid double slashes if baseURL already ends with one
        }
        path += "/models"
        urlComponents.path = path
        
        guard let url = urlComponents.url else {
            throw NSError(domain: "EndpointsViewModel", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not construct models URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        if let token = apiToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if let orgID = organizationID, !orgID.isEmpty {
            request.setValue(orgID, forHTTPHeaderField: "OpenAI-Organization")
        }
        
        print("Fetching models from: \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "EndpointsViewModel", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server"])
        }
        
        print("Models endpoint status code: \(httpResponse.statusCode)")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("Error response body: \(responseBody)")
            throw NSError(domain: "EndpointsViewModel", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch models. Status: \(httpResponse.statusCode). \(responseBody)"])
        }
        
        do {
            // Define expected JSON structure
            struct Model: Codable {
                let id: String
            }
            struct ModelsResponse: Codable {
                let data: [Model]
            }
            
            let decodedResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)
            let modelIDs = decodedResponse.data.map { $0.id }.sorted()
            print("Successfully fetched \(modelIDs.count) models.")
            return modelIDs
        } catch {
            print("Failed to decode models response: \(error)")
            let responseBody = String(data: data, encoding: .utf8) ?? "Could not read response body"
            print("Problematic response body: \(responseBody)")
            throw NSError(domain: "EndpointsViewModel", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to decode models response: \(error.localizedDescription). Response: \(responseBody)"])
        }
    }
}
