import SwiftUI

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
                
                Toggle("Use Chat Endpoint", isOn: $storage.useChatEndpoint)
                    .help("Use /v1/chat/completions instead of /v1/completions")
                
                Button("Save & Load Models") {
                    saveSettings()
                    fetchAvailableModels()
                }
                .disabled(storage.apiEndpoint.isEmpty)
            }
            
            Section(header: Text("Model Selection")) {
                if isLoadingModels {
                    ProgressView("Loading models...")
                } else if let error = modelLoadError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                } else if !availableModels.isEmpty {
                    Picker("Model", selection: $storage.preferredModel) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                } else {
                    Text("Click 'Save & Load Models' to fetch available models")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            Section(header: Text("Default Prompt")) {
                TextField("Prompt", text: $storage.prompt)
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
        isLoadingModels = true
        modelLoadError = nil
        
        // Construct the models endpoint URL
        guard var baseURL = URL(string: storage.apiEndpoint) else {
            modelLoadError = "Invalid API endpoint URL"
            isLoadingModels = false
            return
        }
        
        // If the endpoint ends with "/chat/completions" or similar, get the base URL
        if baseURL.lastPathComponent == "completions" || baseURL.lastPathComponent == "chat" {
            baseURL = baseURL.deletingLastPathComponent()
        }
        
        let modelsURL = baseURL.appendingPathComponent("v1/models")
        
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(storage.apiToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoadingModels = false
                
                if let error = error {
                    modelLoadError = "Error: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    modelLoadError = "No data received"
                    return
                }
                
                // Try to parse the response
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let models = json["data"] as? [[String: Any]] {
                        // Extract model IDs from the response
                        availableModels = models.compactMap { modelData in
                            modelData["id"] as? String
                        }
                        
                        // Filter for chat models if needed
//                        availableModels = availableModels.filter { model in
//                            model.contains("gpt") || model.contains("llama") || model.contains("chat")
//                        }
                        
                        // Sort models alphabetically
                        availableModels.sort()
                        
                        // Set default model if needed
                        if storage.preferredModel.isEmpty && !availableModels.isEmpty {
                            storage.preferredModel = availableModels.first ?? "gpt-3.5-turbo"
                        }
                    } else {
                        modelLoadError = "Invalid response format"
                    }
                } catch {
                    modelLoadError = "Error parsing response: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
}
