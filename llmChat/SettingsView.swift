import SwiftUI
import Combine

struct SettingsView: View {
    @StateObject private var storage = AppStorageManager()
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var modelLoadError: String?
    @State private var selectedModel: String = ""
    
    var body: some View {
        Form {
            Section(header: Text("API Configuration")) {
                TextField("API Token", text: $storage.apiToken)
                    .textContentType(.none)
                    .autocapitalization(.none)
                
                TextField("API Endpoint", text: $storage.apiEndpoint)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    .disabled(true) // Make endpoint URL read-only
                
                Toggle("Use Chat Endpoint", isOn: $storage.useChatEndpoint)
                    .help("Use /v1/chat/completions instead of /v1/completions")
                    .disabled(true) // Make endpoint type read-only
                
                // Endpoint selection menu
                if !storage.savedEndpoints.isEmpty {
                    Menu {
                        ForEach(storage.savedEndpoints) { endpoint in
                            Button(endpoint.name) {
                                storage.selectEndpoint(id: endpoint.id)
                            }
                        }
                    } label: {
                        Label("Select Saved Endpoint", systemImage: "network")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
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
            
            Section(header: Text("Default Prompt")) {
                // Display current prompt in a text editor
                TextEditor(text: $storage.prompt)
                    .frame(minHeight: 100)
                
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
                    ForEach(["English", "Spanish", "French", "German", "Chinese", "Japanese"], id: \.self) { language in
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
            
            // Initialize selected model from storage
            selectedModel = storage.preferredModel
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
        guard !storage.apiEndpoint.isEmpty else { return }
        
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
        
        // Create URL request
        guard let url = URL(string: modelsURL) else {
            isLoadingModels = false
            modelLoadError = "Invalid URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add authorization header if needed
        if !storage.apiToken.isEmpty {
            request.addValue("Bearer \(storage.apiToken)", forHTTPHeaderField: "Authorization")
        }
        
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
                        
                    // Sort models alphabetically
                    self.availableModels.sort()
                    
                    if self.availableModels.isEmpty {
                        self.modelLoadError = "No models found or unsupported format"
                    } else if !self.availableModels.contains(self.storage.preferredModel) || self.storage.preferredModel.isEmpty {
                        // Set preferred model to the first available model if current one isn't available
                        self.storage.preferredModel = self.availableModels.first ?? "gpt-3.5-turbo"
                    }
                } catch {
                    self.modelLoadError = "Failed to parse response: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
}
