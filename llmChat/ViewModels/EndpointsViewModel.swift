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
}
