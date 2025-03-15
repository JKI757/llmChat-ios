import SwiftUI
import Combine

struct EndpointsView: View {
    @EnvironmentObject var storage: AppStorageManager
    @State private var isAddingEndpoint = false
    @State private var isEditingEndpoint = false
    @State private var editingEndpointID: UUID?
    @State private var endpointName = ""
    @State private var endpointURL = ""
    @State private var baseURL = ""
    @State private var apiType = "chat/completions"
    @State private var isChatEndpoint = true
    @State private var requiresAuth = true
    @State private var defaultModel = "gpt-3.5-turbo"
    @State private var temperature: Double = 1.0
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var modelLoadError: String? = nil
    @State private var tempApiToken = ""
    @State private var isEditMode = false
    
    // Dictionary to store API tokens for each endpoint
    @AppStorage("endpointTokens") private var endpointTokensData: Data = Data()
    
    // Get the current tokens dictionary
    private func getEndpointTokens() -> [String: String] {
        if let decoded = try? JSONDecoder().decode([String: String].self, from: endpointTokensData) {
            return decoded
        }
        return [:]
    }
    
    // Save the tokens dictionary
    private func saveEndpointTokens(_ tokens: [String: String]) {
        if let encoded = try? JSONEncoder().encode(tokens) {
            endpointTokensData = encoded
        }
    }
    
    // API endpoint types
    let apiTypes = [
        "chat/completions": "Chat API",
        "completions": "Completion API",
        "models": "Models API",
        "embeddings": "Embeddings API"
    ]
    
    var body: some View {
        List {
            ForEach(storage.savedEndpoints, id: \.id) { endpoint in
                HStack {
                    // No reorder handle needed
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(endpoint.name)
                                .font(.headline)
                            
                            if endpoint.id == storage.defaultEndpointID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                            }
                        }
                        
                        Text(endpoint.url)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        HStack {
                            Label(
                                endpoint.isChatEndpoint ? "Chat API" : "Completion API",
                                systemImage: endpoint.isChatEndpoint ? "bubble.left.and.bubble.right" : "text.bubble"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text("Model: \(endpoint.defaultModel)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Spacer()
                    
                    Button(action: {
                        storage.setDefaultEndpoint(id: endpoint.id)
                    }) {
                        Image(systemName: "star")
                            .foregroundColor(endpoint.id == storage.defaultEndpointID ? .yellow : .gray)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    // Open edit window when tapping on a row
                    editingEndpointID = endpoint.id
                    endpointName = endpoint.name
                    endpointURL = endpoint.url
                    parseEndpointURL(endpoint.url)
                    isChatEndpoint = endpoint.isChatEndpoint
                    requiresAuth = endpoint.requiresAuth
                    defaultModel = endpoint.defaultModel
                    temperature = endpoint.temperature
                    
                    // Load the saved API token for this endpoint
                    tempApiToken = getEndpointTokens()[endpoint.id.uuidString] ?? ""
                    
                    isEditingEndpoint = true
                }
                .simultaneousGesture(LongPressGesture().onEnded { _ in
                    // Select this endpoint on long press
                    storage.selectEndpoint(id: endpoint.id)
                    // Reload available models for this endpoint
                    loadModelsForEndpoint(endpoint)
                    // Show a confirmation
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                })
                .contextMenu {
                    Button(action: {
                        storage.selectEndpoint(id: endpoint.id)
                        // Reload available models for this endpoint
                        loadModelsForEndpoint(endpoint)
                        // Show a confirmation
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    }) {
                        Label("Use This Endpoint", systemImage: "arrow.right.circle")
                    }
                    
                    Button(action: {
                        storage.setDefaultEndpoint(id: endpoint.id)
                    }) {
                        Label("Set as Default", systemImage: "star")
                    }
                    
                    Button(action: {
                        editingEndpointID = endpoint.id
                        endpointName = endpoint.name
                        endpointURL = endpoint.url
                        parseEndpointURL(endpoint.url)
                        isChatEndpoint = endpoint.isChatEndpoint
                        requiresAuth = endpoint.requiresAuth
                        defaultModel = endpoint.defaultModel
                        temperature = endpoint.temperature
                        isEditingEndpoint = true
                    }) {
                        Label("Edit", systemImage: "pencil")
                    }
                }
            }
            .onDelete(perform: storage.deleteEndpoint)
        }
        .navigationTitle("Endpoint Library")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    resetEndpointForm()
                    isAddingEndpoint = true
                }) {
                    Image(systemName: "plus")
                }
            }
            
            // No toolbar items at the bottom
        }
        // No edit button needed
        .sheet(isPresented: $isAddingEndpoint) {
            endpointEditorView(title: "Add New Endpoint", buttonTitle: "Add") {
                // Store only the base URL, not the full URL with API path
                // Save the API token if authentication is required
                if requiresAuth && !tempApiToken.isEmpty {
                    let newEndpointID = storage.addEndpoint(
                        name: endpointName,
                        url: baseURL, // Store only the base URL
                        isChatEndpoint: isChatEndpoint,
                        requiresAuth: requiresAuth,
                        defaultModel: defaultModel,
                        temperature: temperature
                    )
                    
                    // Store the API token for this endpoint using the new method
                    storage.saveAPIToken(for: newEndpointID, token: tempApiToken)
                    
                    // Debug logging
                    print("Saved API token for new endpoint \(endpointName): \(tempApiToken.prefix(5))...\(tempApiToken.suffix(5))")
                    
                    // Automatically select the newly created endpoint
                    storage.selectEndpoint(id: newEndpointID)
                } else {
                    let newEndpointID = storage.addEndpoint(
                        name: endpointName,
                        url: baseURL, // Store only the base URL
                        isChatEndpoint: isChatEndpoint,
                        requiresAuth: requiresAuth,
                        defaultModel: defaultModel,
                        temperature: temperature
                    )
                    // Automatically select the newly created endpoint
                    storage.selectEndpoint(id: newEndpointID)
                }
                isAddingEndpoint = false
            }
        }
        .sheet(isPresented: $isEditingEndpoint) {
            endpointEditorView(title: "Edit Endpoint", buttonTitle: "Save") {
                if let id = editingEndpointID {
                    // Update the endpoint
                    storage.updateEndpoint(
                        id: id,
                        name: endpointName,
                        url: baseURL, // Store only the base URL
                        isChatEndpoint: isChatEndpoint,
                        requiresAuth: requiresAuth,
                        defaultModel: defaultModel,
                        temperature: temperature
                    )
                    
                    // Save the API token if authentication is required
                    if requiresAuth {
                        if !tempApiToken.isEmpty {
                            storage.saveAPIToken(for: id, token: tempApiToken)
                            print("Updated API token for endpoint \(endpointName): \(tempApiToken.prefix(5))...\(tempApiToken.suffix(5))")
                        } else {
                            // For empty tokens, still save it (which effectively clears it)
                            storage.saveAPIToken(for: id, token: "")
                            print("Removed API token for endpoint \(endpointName)")
                        }
                    }
                    
                    // Re-select the endpoint to apply any changes
                    storage.selectEndpoint(id: id)
                }
                isEditingEndpoint = false
            }
        }
    }
    
    private func resetEndpointForm() {
        endpointName = ""
        baseURL = ""
        apiType = "chat/completions"
        endpointURL = ""
        isChatEndpoint = true
        requiresAuth = true
        defaultModel = "gpt-3.5-turbo"
        temperature = 1.0
        tempApiToken = ""
        availableModels = []
        modelLoadError = nil
    }
    
    private func parseEndpointURL(_ url: String) {
        // Extract base URL and API type from the full URL
        baseURL = ""
        apiType = "chat/completions"
        
        if url.contains("/v1/") {
            if let range = url.range(of: "/v1/") {
                baseURL = String(url[..<range.lowerBound])
                let remaining = String(url[range.upperBound...])
                
                if remaining.starts(with: "chat/completions") {
                    apiType = "chat/completions"
                    isChatEndpoint = true
                } else if remaining.starts(with: "completions") {
                    apiType = "completions"
                    isChatEndpoint = false
                } else if remaining.starts(with: "models") {
                    apiType = "models"
                } else if remaining.starts(with: "embeddings") {
                    apiType = "embeddings"
                }
            }
        } else {
            // If no v1 pattern, just use the URL as is
            baseURL = url
            
            // Check if the URL already has a path component that matches one of our API types
            if url.hasSuffix("/chat/completions") {
                baseURL = String(url.dropLast("/chat/completions".count))
                apiType = "chat/completions"
                isChatEndpoint = true
            } else if url.hasSuffix("/completions") {
                baseURL = String(url.dropLast("/completions".count))
                apiType = "completions"
                isChatEndpoint = false
            } else if url.hasSuffix("/models") {
                baseURL = String(url.dropLast("/models".count))
                apiType = "models"
            } else if url.hasSuffix("/embeddings") {
                baseURL = String(url.dropLast("/embeddings".count))
                apiType = "embeddings"
            }
        }
        
        // Remove any trailing slashes from the base URL
        while baseURL.hasSuffix("/") {
            baseURL = String(baseURL.dropLast())
        }
    }
    
    private func constructFullURL() -> String {
        if baseURL.isEmpty {
            return ""
        }
        
        // Clean the base URL - remove any trailing slashes
        var cleanBaseURL = baseURL
        while cleanBaseURL.hasSuffix("/") {
            cleanBaseURL = String(cleanBaseURL.dropLast())
        }
        
        // For display purposes only - the actual stored URL will be just the base URL
        let fullURL = cleanBaseURL + "/v1/" + apiType
        
        // Update isChatEndpoint based on API type
        isChatEndpoint = apiType == "chat/completions"
        
        return fullURL
    }
    
    // Helper function to load models for a specific endpoint
    private func loadModelsForEndpoint(_ endpoint: SavedEndpoint) {
        // Set up the UI state for model loading
        baseURL = endpoint.url
        requiresAuth = endpoint.requiresAuth
        tempApiToken = getEndpointTokens()[endpoint.id.uuidString] ?? ""
        
        // Load the models
        loadModels()
    }
    
    private func loadModels() {
        guard !baseURL.isEmpty else { return }
        
        isLoadingModels = true
        modelLoadError = nil
        availableModels = []
        
        // Clean the base URL - remove any trailing slashes
        var cleanBaseURL = baseURL
        while cleanBaseURL.hasSuffix("/") {
            cleanBaseURL = String(cleanBaseURL.dropLast())
        }
        
        // Construct the models endpoint URL
        let modelsURL = cleanBaseURL + "/v1/models"
        
        // Create URL request
        guard let url = URL(string: modelsURL) else {
            isLoadingModels = false
            modelLoadError = "Invalid URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add authorization header if required
        if requiresAuth {
            if !tempApiToken.isEmpty {
                request.addValue("Bearer \(tempApiToken)", forHTTPHeaderField: "Authorization")
            } else {
                // If auth is required but no token is provided, show an error
                isLoadingModels = false
                modelLoadError = "Authentication is required but no API token is provided"
                return
            }
        }
        
        // Make the request
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoadingModels = false
                
                if let error = error {
                    self.modelLoadError = "Error: \(error.localizedDescription)"
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.modelLoadError = "Invalid response"
                    return
                }
                
                if httpResponse.statusCode != 200 {
                    self.modelLoadError = "Error: HTTP \(httpResponse.statusCode)"
                    return
                }
                
                guard let data = data else {
                    self.modelLoadError = "No data received"
                    return
                }
                
                // Try to parse the response
                do {
                    // First try OpenAI format
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let dataArray = json["data"] as? [[String: Any]] {
                        // OpenAI format
                        self.availableModels = dataArray.compactMap { $0["id"] as? String }
                    } else if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let models = json["models"] as? [[String: Any]] {
                        // Alternative format with 'models' key
                        self.availableModels = models.compactMap { $0["id"] as? String }
                    } else if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let models = json["results"] as? [[String: Any]] {
                        // Alternative format with 'results' key
                        self.availableModels = models.compactMap { $0["id"] as? String }
                    } else {
                        // Try to find any array that might contain model information
                        let json = try JSONSerialization.jsonObject(with: data)
                        if let topLevelArray = json as? [[String: Any]] {
                            // Direct array of models
                            self.availableModels = topLevelArray.compactMap { $0["id"] as? String }
                        } else if let dict = json as? [String: Any] {
                            // Look for any array in the top-level dictionary
                            for (_, value) in dict {
                                if let modelsArray = value as? [[String: Any]] {
                                    self.availableModels = modelsArray.compactMap { $0["id"] as? String }
                                    if !self.availableModels.isEmpty {
                                        break
                                    }
                                }
                            }
                        }
                    }
                    
                    if self.availableModels.isEmpty {
                        self.modelLoadError = "No models found or unsupported format"
                    } else if !self.availableModels.contains(self.defaultModel) {
                        // Set default model to the first available model if current one isn't available
                        self.defaultModel = self.availableModels.first ?? "gpt-3.5-turbo"
                    }
                } catch {
                    self.modelLoadError = "Failed to parse response: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    private func endpointEditorView(title: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        NavigationView {
            Form {
                Section(header: Text("Endpoint Details")) {
                    TextField("Name", text: $endpointName)
                    
                    TextField("Base URL", text: $baseURL)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .onChange(of: baseURL) { _ in
                            endpointURL = constructFullURL()
                        }
                    
                    Picker("API Type", selection: $apiType) {
                        ForEach(Array(apiTypes.keys.sorted()), id: \.self) { key in
                            Text(apiTypes[key] ?? key).tag(key)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: apiType) { _ in
                        endpointURL = constructFullURL()
                    }
                    
                    Text("Full URL: \(endpointURL)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Configuration")) {
                    Toggle("Requires Authentication", isOn: $requiresAuth)
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                    
                    if requiresAuth {
                        TextField("API Token", text: $tempApiToken)
                            .textContentType(.none)
                            .autocapitalization(.none)
                    }
                    
                    if availableModels.isEmpty {
                        TextField("Default Model", text: $defaultModel)
                            .autocapitalization(.none)
                        
                        Button(action: {
                            loadModels()
                        }) {
                            HStack {
                                Text("Load Available Models")
                                if isLoadingModels {
                                    Spacer()
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                }
                            }
                        }
                        .disabled(endpointURL.isEmpty)
                        
                        if let error = modelLoadError {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    } else {
                        Picker("Default Model", selection: $defaultModel) {
                            ForEach(availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        
                        // Temperature slider
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Temperature: \(temperature, specifier: "%.1f")")
                                Spacer()
                                Text(temperature < 0.3 ? "More predictable" : 
                                     temperature > 0.7 ? "More creative" : "Balanced")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $temperature, in: 0.0...2.0, step: 0.1)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section(header: Text("Help"), footer: Text("For OpenAI, use endpoints like 'https://api.openai.com/v1/chat/completions' (Chat) or 'https://api.openai.com/v1/completions' (Completion). For other providers, check their API documentation.")) {
                    // Help text is in the footer
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isAddingEndpoint = false
                        isEditingEndpoint = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(buttonTitle) {
                        action()
                    }
                    .disabled(endpointName.isEmpty || endpointURL.isEmpty || defaultModel.isEmpty)
                }
            }
        }
    }
}

struct EndpointsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            EndpointsView()
        }
    }
}
