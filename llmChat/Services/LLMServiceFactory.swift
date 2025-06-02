import Foundation

/// Factory for creating LLM service instances
enum LLMServiceFactory {
    /// Creates an appropriate LLM service based on the endpoint type
    /// - Parameters:
    ///   - endpoint: The endpoint configuration
    ///   - apiToken: API token for remote services (if required)
    /// - Returns: An instance of a service conforming to LLMServiceProtocol
    /// - Throws: LLMServiceError if the service cannot be created
    static func createService(
        endpoint: SavedEndpoint,
        apiToken: String? = nil
    ) throws -> any LLMServiceProtocol {
        switch endpoint.endpointType {
        case .localModel:
            // Handle local model
            guard let modelURL = URL(string: endpoint.url) else {
                throw ServiceError.invalidEndpoint(endpoint.url)
            }
            
            // Check if the model file exists
            if !FileManager.default.fileExists(atPath: modelURL.path) {
                throw ServiceError.modelNotFound(modelURL.lastPathComponent)
            }
            
            return LocalLLMService(
                modelURL: modelURL,
                maxTokens: endpoint.maxTokens ?? 4096
            )
            
        case .openAI, .customAPI:
            // Handle remote API (OpenAI or compatible)
            if endpoint.requiresAuth {
                guard let token = apiToken, !token.isEmpty else {
                    throw ServiceError.missingToken
                }
                
                return OpenAILLMService(
                    apiKey: token,
                    organizationID: endpoint.organizationID
                )
            } else {
                // For endpoints that don't require auth
                return OpenAILLMService(apiKey: "")
            }
        }
    }
    
    /// Creates a service for a default configuration
    /// - Parameter storage: The app storage manager containing configuration
    /// - Returns: An instance of a service if configuration is valid
    /// - Throws: ServiceError if the service cannot be created
    static func createDefaultService(
        storage: any AppStorageManagerProtocol
    ) throws -> any LLMServiceProtocol {
        guard let defaultEndpointID = storage.defaultEndpointID,
              let endpoint = storage.savedEndpoints.first(where: { $0.id == defaultEndpointID }) else {
            // If no default endpoint is set but we have endpoints, use the first one
            if let firstEndpoint = storage.savedEndpoints.first {
                return try createService(
                    endpoint: firstEndpoint,
                    apiToken: storage.getToken(for: firstEndpoint.id)
                )
            }
            throw ServiceError.noDefaultEndpoint
        }
        
        return try createService(
            endpoint: endpoint,
            apiToken: storage.getToken(for: endpoint.id)
        )
    }
}

// MARK: - Error Types

enum ServiceError: LocalizedError {
    case invalidEndpoint(String)
    case modelNotFound(String)
    case missingToken
    case noDefaultEndpoint
    case unsupportedEndpointType
    
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let url):
            return "Invalid endpoint URL: \(url)"
        case .modelNotFound(let filename):
            return "Model file not found: \(filename)"
        case .missingToken:
            return "API token is required for this endpoint"
        case .noDefaultEndpoint:
            return "No default endpoint configured"
        case .unsupportedEndpointType:
            return "Unsupported endpoint type"
        }
    }
}
