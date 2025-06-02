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
    @State private var temperature: Double
    @State private var apiToken: String
    @State private var organizationID: String
    @State private var maxTokens: String
    @State private var isImportingFile = false
    @State private var isLocalFileSelected = false
    @State private var selectedFileURL: URL?
    
    private let endpoint: SavedEndpoint?
    
    // MARK: - Initialization
    
    init(viewModel: EndpointsViewModel, endpoint: SavedEndpoint? = nil) {
        self.viewModel = viewModel
        self.endpoint = endpoint
        
        // Initialize state properties
        _name = State(initialValue: endpoint?.name ?? "")
        _url = State(initialValue: endpoint?.url ?? "")
        _endpointType = State(initialValue: endpoint?.endpointType ?? .openAI)
        _isChatEndpoint = State(initialValue: endpoint?.isChatEndpoint ?? true)
        _requiresAuth = State(initialValue: endpoint?.requiresAuth ?? true)
        _defaultModel = State(initialValue: endpoint?.defaultModel ?? "")
        _temperature = State(initialValue: endpoint?.temperature ?? 0.7)
        _apiToken = State(initialValue: endpoint?.id != nil ? viewModel.getToken(for: endpoint!.id) : "")
        _organizationID = State(initialValue: endpoint?.organizationID ?? "")
        _maxTokens = State(initialValue: endpoint?.maxTokens != nil ? "\(endpoint!.maxTokens!)" : "2048")
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            FormContent()
                .navigationTitle(endpoint == nil ? "Add Endpoint" : "Edit Endpoint")
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
    }
    
    // MARK: - Form Content
    
    private func FormContent() -> some View {
        Form {
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
                TextField("Default Model", text: $defaultModel)
                
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
        
        let endpoint = SavedEndpoint(
            id: endpoint?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            url: url.trimmingCharacters(in: .whitespaces),
            defaultModel: defaultModel.trimmingCharacters(in: .whitespaces),
            maxTokens: maxTokensValue,
            requiresAuth: endpointType == .localModel ? false : requiresAuth,
            organizationID: orgID,
            endpointType: endpointType,
            isChatEndpoint: endpointType == .localModel ? true : isChatEndpoint,
            temperature: temperature
        )
        
        let token = (requiresAuth && !apiToken.isEmpty) ? apiToken : nil
        
        viewModel.saveEndpoint(endpoint, token: token)
    }
}
