import Foundation

/// Represents a saved LLM endpoint configuration
struct SavedEndpoint: Identifiable, Codable, Hashable, Equatable {
    /// Unique identifier for the endpoint
    var id: UUID
    
    /// Display name for the endpoint
    var name: String
    
    /// URL for the endpoint (API URL or file URL for local models)
    var url: String
    
    /// Default model to use with this endpoint
    var defaultModel: String
    
    /// Maximum tokens for responses (optional)
    var maxTokens: Int?
    
    /// Whether the endpoint requires authentication
    var requiresAuth: Bool
    
    /// Organization ID for the endpoint (optional)
    var organizationID: String?
    
    /// Type of endpoint
    var endpointType: EndpointType
    
    /// Whether this endpoint supports chat completion format
    var isChatEndpoint: Bool
    
    /// Temperature setting for the model
    var temperature: Double
    
    /// Last time this endpoint was used
    var lastUsed: Date?
    
    /// When this endpoint was created
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        url: String,
        defaultModel: String = "gpt-3.5-turbo",
        maxTokens: Int? = nil,
        requiresAuth: Bool = true,
        organizationID: String? = nil,
        endpointType: EndpointType = .openAI,
        isChatEndpoint: Bool = true,
        temperature: Double = 1.0,
        lastUsed: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.defaultModel = defaultModel
        self.maxTokens = maxTokens
        self.requiresAuth = requiresAuth
        self.organizationID = organizationID
        self.endpointType = endpointType
        self.isChatEndpoint = isChatEndpoint
        self.temperature = temperature
        self.lastUsed = lastUsed
        self.createdAt = createdAt
    }
}

/// Type of endpoint
enum EndpointType: String, Codable, CaseIterable {
    case openAI = "OpenAI"
    case localModel = "Local Model"
    case customAPI = "Custom API"
    
    var displayName: String { rawValue }
}

// MARK: - Convenience Properties

extension SavedEndpoint {
    /// Whether this endpoint is for a local model
    var isLocalModel: Bool {
        return endpointType == .localModel
    }
}

// MARK: - Codable

extension SavedEndpoint {
    enum CodingKeys: String, CodingKey {
        case id, name, url, endpointType, isChatEndpoint, requiresAuth
        case defaultModel, temperature, organizationID, maxTokens, lastUsed, createdAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        endpointType = try container.decodeIfPresent(EndpointType.self, forKey: .endpointType) ?? .openAI
        isChatEndpoint = try container.decodeIfPresent(Bool.self, forKey: .isChatEndpoint) ?? true
        requiresAuth = try container.decodeIfPresent(Bool.self, forKey: .requiresAuth) ?? true
        defaultModel = try container.decodeIfPresent(String.self, forKey: .defaultModel) ?? "gpt-3.5-turbo"
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 1.0
        organizationID = try container.decodeIfPresent(String.self, forKey: .organizationID)
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens)
        lastUsed = try container.decodeIfPresent(Date.self, forKey: .lastUsed)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

// MARK: - Helper Methods

extension SavedEndpoint {
    /// Updates the last used timestamp to now
    func withUpdatedLastUsed() -> SavedEndpoint {
        var updated = self
        updated.lastUsed = Date()
        return updated
    }
}

// MARK: - Default Endpoints

extension SavedEndpoint {
    /// Creates a default OpenAI endpoint configuration
    static var defaultOpenAI: SavedEndpoint {
        SavedEndpoint(
            name: "OpenAI",
            url: "https://api.openai.com",
            defaultModel: "gpt-3.5-turbo",
            requiresAuth: true,
            endpointType: .openAI,
            isChatEndpoint: true,
            temperature: 1.0,
            createdAt: Date()
        )
    }
    
    /// Creates a default local model endpoint configuration
    static func defaultLocal(modelPath: String) -> SavedEndpoint {
        SavedEndpoint(
            name: "Local Model",
            url: modelPath,
            defaultModel: URL(fileURLWithPath: modelPath).lastPathComponent,
            maxTokens: 2048,
            requiresAuth: false,
            endpointType: .localModel,
            isChatEndpoint: true,
            temperature: 0.7,
            createdAt: Date()
        )
    }
}

// MARK: - Hashable

extension SavedEndpoint {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: SavedEndpoint, rhs: SavedEndpoint) -> Bool {
        lhs.id == rhs.id
    }
}
