import SwiftUI

struct EndpointsView: View {
    @StateObject private var viewModel: EndpointsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false
    @State private var endpointToDelete: SavedEndpoint?
    @State private var editMode = EditMode.inactive
    
    init(storage: AppStorageManager) {
        _viewModel = StateObject(wrappedValue: EndpointsViewModel(storage: storage))
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.endpoints) { endpoint in
                    EndpointRow(
                        endpoint: endpoint,
                        isDefault: endpoint.id == viewModel.defaultEndpointID,
                        onSetDefault: { viewModel.setDefaultEndpoint(endpoint) },
                        onEdit: { viewModel.editEndpoint(endpoint) }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            endpointToDelete = endpoint
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        
                        Button {
                            viewModel.editEndpoint(endpoint)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
                .onDelete { indexSet in
                    viewModel.deleteEndpoints(at: indexSet)
                }
                
                if viewModel.endpoints.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No Endpoints")
                            .font(.headline)
                        Text("Add your first endpoint to get started")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(40)
                    .listRowSeparator(.hidden)
                }
            }
            .navigationTitle("Endpoints")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { viewModel.showingAddEndpoint = true }) {
                        Image(systemName: "plus")
                    }
                }
                
                if !viewModel.endpoints.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton()
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .refreshable {
                await viewModel.refreshEndpoints()
            }
            .sheet(isPresented: $viewModel.showingAddEndpoint) {
                EndpointFormView(viewModel: viewModel)
            }
            .sheet(item: $viewModel.editingEndpoint) { endpoint in
                EndpointFormView(viewModel: viewModel, endpoint: endpoint)
            }
            .alert("Delete Endpoint", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let endpoint = endpointToDelete,
                       let index = viewModel.endpoints.firstIndex(where: { $0.id == endpoint.id }) {
                        viewModel.deleteEndpoints(at: IndexSet(integer: index))
                    }
                }
            } message: {
                Text("Are you sure you want to delete this endpoint? This action cannot be undone.")
            }
            .alert("Error", isPresented: $viewModel.showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
        }
    }
}

// MARK: - Endpoint Row

struct EndpointRow: View {
    let endpoint: SavedEndpoint
    let isDefault: Bool
    let onSetDefault: () -> Void
    let onEdit: () -> Void
    @State private var showingConfirmation = false
    
    private var iconName: String {
        switch endpoint.endpointType {
        case .openAI: return "sparkles"
        case .localModel: return "desktopcomputer"
        case .customAPI: return "network"
        }
    }
    
    private var iconColor: Color {
        switch endpoint.endpointType {
        case .openAI: return .green
        case .localModel: return .orange
        case .customAPI: return .purple
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .font(.system(size: 16, weight: .semibold))
            }
            
            // Details
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(endpoint.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if isDefault {
                        Text("Default")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                    
                    if endpoint.endpointType == .localModel {
                        Text("Local")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
                
                Text(endpoint.endpointType.displayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if !endpoint.isLocalModel, let url = URL(string: endpoint.url) {
                    Text(url.host ?? endpoint.url)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Actions
            if !isDefault {
                Button(action: {
                    onSetDefault()
                    showingConfirmation = true
                }) {
                    Text("Set Default")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                }
                .overlay(
                    Group {
                        if showingConfirmation {
                            Text("✓ Set as default")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.1))
                                .foregroundColor(.green)
                                .cornerRadius(8)
                                .transition(.opacity)
                        }
                    }
                )
                .onChange(of: showingConfirmation) { newValue in
                    if newValue {
                        // Auto-hide the confirmation after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showingConfirmation = false
                        }
                    }
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

struct EndpointsView_Previews: PreviewProvider {
    static var previews: some View {
        let storage = AppStorageManager.shared
        storage.savedEndpoints = [
            SavedEndpoint(
                name: "OpenAI",
                url: "https://api.openai.com/v1",
                defaultModel: "gpt-3.5-turbo",
                requiresAuth: true,
                endpointType: .openAI,
                isChatEndpoint: true
            ),
            SavedEndpoint(
                name: "Local Model",
                url: "/path/to/model.gguf",
                defaultModel: "llama-2-7b",
                requiresAuth: false,
                endpointType: .localModel,
                isChatEndpoint: true
        )
    ]
    storage.defaultEndpointID = storage.savedEndpoints[0].id
        
    return EndpointsView(storage: storage)
    }
}
