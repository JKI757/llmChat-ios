import SwiftUI
import Combine

struct SettingsView: View {
    @EnvironmentObject var storage: AppStorageManager
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var modelLoadError: String?
    
    var body: some View {
        Form {
            Section(header: Text("API Configuration")) {
                // Endpoint picker
                if !storage.savedEndpoints.isEmpty {
                    // Find the currently selected endpoint
                    let currentEndpointID = storage.savedEndpoints.first(where: { $0.url == storage.apiEndpoint })?.id ?? UUID()
                    
                    Picker("API Endpoint", selection: Binding<UUID>(
                        get: { currentEndpointID },
                        set: { newID in
                            storage.selectEndpoint(id: newID)
                            // Refresh models when endpoint changes
                            fetchAvailableModels()
                        }
                    )) {
                        ForEach(storage.savedEndpoints) { endpoint in
                            Text(endpoint.name + (endpoint.requiresAuth ? " (Auth)" : "")).tag(endpoint.id)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    // Show the current endpoint details
                    if let selectedEndpoint = storage.savedEndpoints.first(where: { $0.url == storage.apiEndpoint }) {
                        Text("Using: \(selectedEndpoint.url)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("No saved endpoints. Please add an endpoint using the Manage Endpoint Library option below.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Navigation to endpoint library
                NavigationLink(destination: EndpointsView().onDisappear(perform: {
                    // Refresh models when returning from endpoints view
                    fetchAvailableModels()
                })) {
                    Label("Manage Endpoint Library", systemImage: "server.rack")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                
                // Model selection
                if isLoadingModels {
                    HStack {
                        Text("Loading models...")
                        Spacer()
                        ProgressView()
                    }
                } else if !availableModels.isEmpty {
                    Picker("Model", selection: $storage.preferredModel) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    
                    // API Type picker (replacing the toggle)
                    Picker("API Type", selection: $storage.useChatEndpoint) {
                        Text("Chat Completions").tag(true)
                        Text("Completions").tag(false)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .disabled(true) // Make endpoint type read-only
                    .help("Use /v1/chat/completions instead of /v1/completions")
                    
                    // Temperature slider
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Temperature: \(storage.temperature, specifier: "%.1f")")
                            Spacer()
                            Text(storage.temperature < 0.3 ? "More predictable" : 
                                 storage.temperature > 0.7 ? "More creative" : "Balanced")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $storage.temperature, in: 0.0...2.0, step: 0.1)
                    }
                    .padding(.top, 8)
                } else {
                    Button("Load Available Models") {
                        fetchAvailableModels()
                    }
                    .disabled(storage.apiEndpoint.isEmpty)
                    
                    if let error = modelLoadError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            
            // Model Selection section removed as it's now integrated in the API Configuration section
            
            Section(header: Text("Default Prompts")) {
                // System Prompt section
                VStack(alignment: .leading) {
                    Text("System Prompt")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $storage.systemPrompt)
                        .frame(minHeight: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
                .padding(.bottom, 8)
                
                // User Prompt section
                VStack(alignment: .leading) {
                    Text("User Prompt (Optional)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $storage.userPrompt)
                        .frame(minHeight: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
                
                // Prompt selection menu
                if !storage.savedPrompts.isEmpty {
                    Menu {
                        ForEach(storage.savedPrompts) { prompt in
                            Button(prompt.name) {
                                storage.selectPrompt(id: prompt.id)
                            }
                        }
                    } label: {
                        Label("Select Saved Prompt", systemImage: "list.bullet")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
                
                // Navigation to prompt library
                NavigationLink(destination: PromptsView()) {
                    Label("Manage Prompt Library", systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
            
            Section(header: Text("Preferred Language")) {
                Picker("Language", selection: $storage.preferredLanguage) {
                    ForEach(AppStorageManager.supportedLanguages, id: \.self) { language in
                        Text(language)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            // If we already have API credentials, try to load models
            if !storage.apiEndpoint.isEmpty {
                fetchAvailableModels()
            }
            
            // No need to initialize selectedModel as we're using storage.preferredModel directly
        }
    }
    
    private func saveSettings() {
        // Save settings to UserDefaults through AppStorageManager
        // This happens automatically through the @Published properties
        
        // Provide user feedback (optional)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    private func fetchAvailableModels() {
        guard !storage.apiEndpoint.isEmpty else { 
            print("Cannot fetch models: API endpoint is empty")
            return 
        }
        
        isLoadingModels = true
        availableModels = []
        modelLoadError = nil
        
        // Extract the base URL from the endpoint URL
        var baseURL = storage.apiEndpoint
        
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
            isLoadingModels = false
            modelLoadError = "Invalid URL"
            print("Invalid models URL: \(modelsURL)")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Set a longer timeout (30 seconds) to accommodate model loading time
        request.timeoutInterval = 30.0
        
        // Add authorization header if needed
        if !storage.apiToken.isEmpty {
            let token = storage.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            print("Using API token for models request: \(token.prefix(5))...\(token.suffix(5))")
        } else {
            print("WARNING: No API token provided for models request")
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoadingModels = false
                
                if let error = error {
                    let errorMessage = "Error: \(error.localizedDescription)"
                    print("Model fetch error: \(errorMessage)")
                    self.modelLoadError = errorMessage
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("Model fetch error: Invalid response type")
                    self.modelLoadError = "Invalid response"
                    return
                }
                
                if httpResponse.statusCode != 200 {
                    let errorMessage = "Error: HTTP \(httpResponse.statusCode)"
                    print("Model fetch error: \(errorMessage)")
                    
                    // Add more specific error messages for common HTTP status codes
                    if httpResponse.statusCode == 401 {
                        self.modelLoadError = "Authentication failed. Please check your API token."
                    } else if httpResponse.statusCode == 403 {
                        self.modelLoadError = "Access forbidden. Your API token may not have permission to list models."
                    } else if httpResponse.statusCode == 404 {
                        self.modelLoadError = "Models endpoint not found. Please check your API endpoint URL."
                    } else if httpResponse.statusCode >= 500 {
                        self.modelLoadError = "Server error (\(httpResponse.statusCode)). Please try again later."
                    } else {
                        self.modelLoadError = errorMessage
                    }
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
                        
                    // Sort models alphabetically
                    self.availableModels.sort()
                    
                    if self.availableModels.isEmpty {
                        print("No models found in API response")
                        self.modelLoadError = "No models found or unsupported format"
                    } else {
                        print("Successfully loaded \(self.availableModels.count) models")
                        
                        // If current model isn't in the list or is empty, select a new one
                        if !self.availableModels.contains(self.storage.preferredModel) || self.storage.preferredModel.isEmpty {
                            let oldModel = self.storage.preferredModel
                            self.storage.preferredModel = self.availableModels.first ?? "gpt-3.5-turbo"
                            print("Changed model from '\(oldModel)' to '\(self.storage.preferredModel)'")
                        } else {
                            print("Current model '\(self.storage.preferredModel)' is valid")
                        }
                    }
                } catch {
                    self.modelLoadError = "Failed to parse response: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
}
