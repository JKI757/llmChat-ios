import SwiftUI

struct EndpointFormView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: EndpointsViewModel
    
    @State private var name: String
    @State private var url: String
    @State private var endpointType: EndpointType
    @State private var isChatEndpoint: Bool
    @State private var requiresAuth: Bool
    @State private var defaultModel: String
    @State private var availableModels: [String] = []
    @State private var newModelName: String = ""
    // Track if view has appeared to prevent state reset
    @State private var hasAppeared: Bool = false
    @State private var temperature: Double
    @State private var apiToken: String
    @State private var organizationID: String
    @State private var maxTokens: String
    @State private var isImportingFile = false
    @State private var isLocalFileSelected = false
    @State private var selectedFileURL: URL?
    @State private var defaultPromptID: UUID?
    @State private var isFetchingModels: Bool = false
    @State private var fetchModelsError: String? = nil
    @State private var showingFetchModelsErrorAlert: Bool = false
    
    private let endpoint: SavedEndpoint?
    
    // MARK: - Initialization
    
    init(viewModel: EndpointsViewModel, endpoint: SavedEndpoint? = nil) {
        self.viewModel = viewModel
        self.endpoint = endpoint
        
        // Debug: Log the endpoint models if it exists
        if let endpoint = endpoint, endpoint.endpointType == .customAPI {
            print("Loading endpoint with models: \(endpoint.availableModels.count)")
            for (i, model) in endpoint.availableModels.enumerated() {
                print("  Initial model \(i): \(model)")
            }
        }
        
        // Initialize state properties
        _name = State(initialValue: endpoint?.name ?? "")
        _url = State(initialValue: endpoint?.url ?? "")
        _endpointType = State(initialValue: endpoint?.endpointType ?? .openAI)
        _isChatEndpoint = State(initialValue: endpoint?.isChatEndpoint ?? true)
        _requiresAuth = State(initialValue: endpoint?.requiresAuth ?? true)
        _defaultModel = State(initialValue: endpoint?.defaultModel ?? "")
        
        // Create a deep copy of the available models to ensure proper state initialization
        var initialModels: [String] = []
        if let endpoint = endpoint {
            // Use the endpoint's available models directly
            initialModels = endpoint.availableModels
            print("Loading endpoint with \(initialModels.count) models from endpoint")
        }
        
        // Make sure default model is included in available models
        if let defaultModel = endpoint?.defaultModel, !defaultModel.isEmpty, !initialModels.contains(defaultModel) {
            initialModels.append(defaultModel)
            print("Added default model to initial models: \(defaultModel)")
        }
        
        _availableModels = State(initialValue: initialModels)
        
        _temperature = State(initialValue: endpoint?.temperature ?? 0.7)
        _apiToken = State(initialValue: endpoint?.id != nil ? viewModel.getToken(for: endpoint!.id) : "")
        _organizationID = State(initialValue: endpoint?.organizationID ?? "")
        _maxTokens = State(initialValue: endpoint?.maxTokens != nil ? "\(endpoint!.maxTokens!)" : "2048")
        _defaultPromptID = State(initialValue: endpoint?.defaultPromptID)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            FormContent()
                .navigationTitle(endpoint == nil ? "Add Endpoint" : "Edit Endpoint")
                .onAppear {
                    // Only initialize once to prevent state reset during view updates
                    if !hasAppeared {
                        print("View appeared, initializing with models: \(availableModels.count)")
                        hasAppeared = true
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            saveEndpoint()
                            dismiss()
                        }
                        .disabled(!isFormValid)
                    }
                    
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
        }
        .alert(isPresented: $showingFetchModelsErrorAlert) {
            Alert(
                title: Text("Error Fetching Models"),
                message: Text(fetchModelsError ?? "An unknown error occurred."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    // MARK: - Form Content
    
    private func FormContent() -> some View {
        Form {
            // Debug info for troubleshooting
            if endpoint?.endpointType == .customAPI {
                Text("Models count: \(availableModels.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            // Basic Information Section
            Section(header: Text("Basic Information")) {
                TextField("Name", text: $name)
                
                Picker("Type", selection: $endpointType) {
                    ForEach(EndpointType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                
                // URL Field
                if endpointType == .localModel {
                    HStack {
                        Text("Model File")
                        Spacer()
                        Button(isLocalFileSelected ? "Change File" : "Select File") {
                            isImportingFile = true
                        }
                        .fileImporter(
                            isPresented: $isImportingFile,
                            allowedContentTypes: [.data],
                            allowsMultipleSelection: false
                        ) { result in
                            handleFileImport(result)
                        }
                    }
                    
                    if isLocalFileSelected, let fileURL = selectedFileURL {
                        Text(fileURL.lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    TextField("URL", text: $url)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }
            }
            
            // Authentication Section
            if endpointType != .localModel {
                Section(header: Text("Authentication")) {
                    Toggle("Requires Authentication", isOn: $requiresAuth)
                    
                    if requiresAuth {
                        SecureField("API Token", text: $apiToken)
                        
                        if endpointType == .openAI {
                            TextField("Organization ID (Optional)", text: $organizationID)
                        }
                    }
                }
            }
            
            // Model Settings Section
            Section(header: Text("Model Settings")) {
                if endpointType == .customAPI || endpointType == .openAI {
                    // For custom APIs, allow multiple models with a default selection
                    Picker("Default Model", selection: $defaultModel) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                        // Add option for empty string if no models are available
                        if availableModels.isEmpty {
                            Text("No models available").tag("")
                        }
                    }
                    .disabled(availableModels.isEmpty)
                    
                    // Default Prompt Picker
                    Picker("Default Prompt", selection: $defaultPromptID) {
                        Text("None").tag(nil as UUID?)
                        ForEach(viewModel.savedPrompts.sorted(by: { $0.name < $1.name })) { prompt in
                            Text(prompt.name).tag(prompt.id as UUID?)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .disabled(viewModel.savedPrompts.isEmpty)
                    
                    if viewModel.savedPrompts.isEmpty {
                        Text("No prompts available. Create prompts in Settings.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Fetch Models Button for OpenAI
                    if endpointType == .openAI {
                        HStack {
                            Button("Fetch Models from Endpoint") {
                                Task {
                                    isFetchingModels = true
                                    fetchModelsError = nil
                                    do {
                                        let fetchedModels = try await viewModel.fetchOpenAIModels(baseURL: url, apiToken: apiToken, organizationID: organizationID)
                                        self.availableModels = fetchedModels
                                        if !fetchedModels.isEmpty && (defaultModel.isEmpty || !fetchedModels.contains(defaultModel)) {
                                            self.defaultModel = fetchedModels.first ?? ""
                                        }
                                        print("Successfully updated available models: \(self.availableModels.count) models.")
                                    } catch {
                                        let nsError = error as NSError
                                        self.fetchModelsError = nsError.localizedDescription
                                        self.showingFetchModelsErrorAlert = true
                                        print("Error fetching models: \(nsError.localizedDescription)")
                                    }
                                    isFetchingModels = false
                                }
                            }
                            .disabled(isFetchingModels || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            
                            if isFetchingModels {
                                ProgressView()
                                    .padding(.leading, 5)
                            }
                        }
                    }
                    
                    // Available Models Section
                    Text("Available Models")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    // Add new model field
                    HStack {
                        TextField("Add Model", text: $newModelName)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        Button(action: {
                            let trimmedName = newModelName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmedName.isEmpty && !availableModels.contains(trimmedName) {
                                availableModels.append(trimmedName)
                                if defaultModel.isEmpty {
                                    defaultModel = trimmedName
                                }
                                newModelName = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                        }
                        .disabled(newModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    
                    // List of models with remove buttons
                    ForEach(availableModels, id: \.self) { model in
                        HStack {
                            Text(model)
                            if model == defaultModel {
                                Text("(Default)")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            Spacer()
                            Button(action: {
                                // Don't allow removing the default model
                                if model != defaultModel {
                                    availableModels.removeAll { $0 == model }
                                }
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .disabled(model == defaultModel)
                        }
                    }
                } else {
                    // For OpenAI and local models, just a simple text field
                    TextField("Default Model", text: $defaultModel)
                }
                
                if endpointType == .localModel {
                    TextField("Max Tokens", text: $maxTokens)
                        .keyboardType(.numberPad)
                }
                
                if endpointType != .localModel {
                    Toggle("Chat Endpoint", isOn: $isChatEndpoint)
                }
                
                VStack(alignment: .leading) {
                    Text("Temperature: \(String(format: "%.1f", temperature))")
                    Slider(value: $temperature, in: 0...2, step: 0.1)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let selectedFile = try result.get().first else { return }
            
            // Start accessing the security-scoped resource
            guard selectedFile.startAccessingSecurityScopedResource() else {
                // Handle the failure here
                return
            }
            
            // Make sure you release the security-scoped resource when finished
            defer { selectedFile.stopAccessingSecurityScopedResource() }
            
            // Now you can copy it to your app's container
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destinationURL = documentsDirectory.appendingPathComponent(selectedFile.lastPathComponent)
            
            // Check if file already exists and remove it
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            try FileManager.default.copyItem(at: selectedFile, to: destinationURL)
            
            // Update UI
            self.selectedFileURL = destinationURL
            self.isLocalFileSelected = true
            self.url = destinationURL.path
            
        } catch {
            print("Error selecting file: \(error.localizedDescription)")
        }
    }
    
    private var isFormValid: Bool {
        if endpointType == .localModel {
            return !url.isEmpty && !defaultModel.trimmingCharacters(in: .whitespaces).isEmpty
        } else {
            guard !url.trimmingCharacters(in: .whitespaces).isEmpty,
                  URL(string: url) != nil else { return false }
            
            if requiresAuth && endpointType == .openAI {
                return !apiToken.trimmingCharacters(in: .whitespaces).isEmpty
            }
            
            return true
        }
    }
    
    private func saveEndpoint() {
        let maxTokensValue = endpointType == .localModel ? Int(maxTokens) : nil
        let orgID = organizationID.isEmpty ? nil : organizationID
        
        // Prepare available models based on endpoint type
        var modelsList: [String] = []
        let trimmedDefault = defaultModel.trimmingCharacters(in: .whitespaces)

        if endpointType == .customAPI || endpointType == .openAI {
            // For Custom API and OpenAI, use the state variable `availableModels` 
            // which holds the manually entered or fetched list.
            modelsList = self.availableModels
            print("Saving models for \(endpointType) endpoint: \(modelsList.count) models from self.availableModels")
            
            // Ensure the default model (if set) is in the list. 
            // This is important if availableModels was empty and defaultModel was typed manually,
            // or if defaultModel was somehow not included in a fetched list it should have been.
            if !trimmedDefault.isEmpty && !modelsList.contains(trimmedDefault) {
                // Check if it's a non-empty default model that's missing
                modelsList.append(trimmedDefault)
                print("  Added default model to modelsList: \(trimmedDefault)")
            }
            // If modelsList is still empty but there's a default model, ensure it's the only one.
            if modelsList.isEmpty && !trimmedDefault.isEmpty {
                modelsList = [trimmedDefault]
            }

        } else if !trimmedDefault.isEmpty {
            // For other types (e.g., .localModel), just include the default model if it's set.
            modelsList = [trimmedDefault]
            print("Saving model for \(endpointType) endpoint: [\(trimmedDefault)]")
        }
        // If modelsList is still empty at this point (e.g. new OpenAI endpoint, no fetch, no default entered), it will be saved as empty.
        print("Final modelsList to be saved for \(name): \(modelsList)")
        
        let endpoint = SavedEndpoint(
            id: endpoint?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            url: url.trimmingCharacters(in: .whitespaces),
            defaultModel: defaultModel.trimmingCharacters(in: .whitespaces),
            availableModels: modelsList,
            maxTokens: maxTokensValue,
            requiresAuth: endpointType == .localModel ? false : requiresAuth,
            organizationID: orgID,
            endpointType: endpointType,
            isChatEndpoint: endpointType == .localModel ? true : isChatEndpoint,
            temperature: temperature,
            defaultPromptID: defaultPromptID
        )
        
        let token = (requiresAuth && !apiToken.isEmpty) ? apiToken : nil
        
        viewModel.saveEndpoint(endpoint, token: token)
    }
}

// MARK: - View Extensions

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {

        ZStack(alignment: alignment) {
            self
            placeholder().opacity(shouldShow ? 1 : 0)
        }
    }
}
