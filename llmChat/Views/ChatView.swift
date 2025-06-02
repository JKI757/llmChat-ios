import SwiftUI
import MarkdownUI

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @EnvironmentObject var storage: AppStorageManager
    @Environment(\.colorScheme) private var colorScheme
    
    // Model selection is now handled by the menu
    @State private var showingSettings = false
    @State private var showingClearConfirmation = false
    @State private var scrollToBottomID: UUID?
    
    private let scrollBottomID = UUID()
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    if viewModel.hasServiceError && viewModel.errorMessage != nil {
                        // Show service configuration error with direct link to settings
                        VStack(spacing: 16) {
                            Spacer()
                            
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 50))
                                .foregroundColor(.orange)
                            
                            Text(viewModel.errorMessage ?? "")
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            Text("Please configure an endpoint in settings to start chatting.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            Button(action: { showingSettings = true }) {
                                HStack {
                                    Image(systemName: "gear")
                                    Text("Open Settings")
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .padding(.top, 8)
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else if viewModel.hasServiceError {
                        // No specific error message but no service available
                        // Just show an empty view with messages list
                        EmptyView()
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                    .padding(.vertical, 4)
                            }
                            
                            // Invisible view at the bottom to scroll to
                            Color.clear
                                .frame(height: 1)
                                .id(scrollBottomID)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                }
                .onChange(of: viewModel.messages) { _ in
                    withAnimation {
                        proxy.scrollTo(scrollBottomID, anchor: .bottom)
                    }
                }
            }
            
            // Input Area
            VStack(spacing: 0) {
                Divider()
                
                // Model and endpoint selector
                Menu {
                    // Endpoint selection section
                    Section("Endpoint") {
                        ForEach(storage.savedEndpoints) { endpoint in
                            Button(action: {
                                storage.setDefaultEndpoint(id: endpoint.id)
                            }) {
                                HStack {
                                    Text(endpoint.name)
                                    if viewModel.selectedEndpoint == endpoint.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button(action: { showingSettings = true }) {
                            Label("Manage Endpoints", systemImage: "gear")
                        }
                    }
                    
                    // Model selection section (only if we have an endpoint selected)
                    if !viewModel.availableModels.isEmpty {
                        Section("Model") {
                            ForEach(viewModel.availableModels, id: \.self) { model in
                                Button(action: {
                                    viewModel.selectedModel = model
                                }) {
                                    HStack {
                                        Text(model)
                                        if viewModel.selectedModel == model {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        // Show endpoint icon based on type
                        if let endpointID = viewModel.selectedEndpoint,
                           let endpoint = storage.savedEndpoints.first(where: { $0.id == endpointID }) {
                            Image(systemName: endpoint.endpointType == .localModel ? "desktopcomputer" : "cloud")
                                .imageScale(.small)
                            
                            // Show endpoint name and model
                            VStack(alignment: .leading, spacing: 2) {
                                Text(endpoint.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(viewModel.selectedModel.isEmpty ? "Select Model" : viewModel.selectedModel)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        } else {
                            Image(systemName: "cpu")
                                .imageScale(.small)
                            
                            Text("Select Endpoint")
                                .lineLimit(1)
                        }
                        
                        if viewModel.isLoadingModels {
                            ProgressView()
                                .padding(.leading, 4)
                        } else {
                            Image(systemName: "chevron.down")
                                .imageScale(.small)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                }
                .disabled(viewModel.isLoadingModels)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .buttonStyle(PlainButtonStyle())
                .disabled(viewModel.availableModels.isEmpty)
                
                HStack(alignment: .bottom, spacing: 8) {
                    // Attachment Button
                    Button(action: {}) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .padding(.leading, 8)
                    .padding(.bottom, 8)
                    
                    // Text Input
                    ZStack(alignment: .trailing) {
                        TextEditor(text: $viewModel.inputText)
                            .frame(minHeight: 40, maxHeight: 120)
                            .padding(8)
                            .background(Color(.systemBackground))
                            .cornerRadius(18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            .padding(.vertical, 8)
                            .disabled((viewModel.hasServiceError && viewModel.errorMessage != nil) || viewModel.isSending)
                            .opacity((viewModel.hasServiceError && viewModel.errorMessage != nil) ? 0.6 : 1.0)
                        
                    }
                    
                    // Send Button
                    Button(action: viewModel.sendMessage) {
                        if viewModel.isSending {
                            ProgressView()
                                .padding(8)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundColor(((viewModel.hasServiceError && viewModel.errorMessage != nil) || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSending) ? .gray : .blue)
                                .padding(8)
                        }
                    }
                    .disabled((viewModel.hasServiceError && viewModel.errorMessage != nil) || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSending)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                }
                .padding(.bottom, 8)
            }
            .background(Color(.systemBackground).opacity(0.8))
        }
        .navigationTitle("LLM Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    // Create a new chat
                    withAnimation {
                        viewModel.clearConversation()
                    }
                }) {
                    Image(systemName: "square.and.pencil")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    if !viewModel.messages.isEmpty {
                        Button(action: { showingClearConfirmation = true }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                    
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationView {
                SettingsView(viewModel: SettingsViewModel())
            }
        }
        // Model selection is now handled by the menu
        .confirmationDialog("Clear Conversation", isPresented: $showingClearConfirmation) {
            Button("Clear", role: .destructive) {
                withAnimation {
                    viewModel.clearConversation()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to clear the conversation? This cannot be undone.")
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
        .onAppear {
            // Initialize with default endpoint if needed
            if viewModel.selectedEndpoint == nil, let defaultID = storage.defaultEndpointID {
                viewModel.selectedEndpoint = defaultID
            }
        }
    }
    
    // Model selection is now handled by the menu in the UI
}

// MARK: - Message Bubble View

struct MessageBubble: View {
    let message: ChatMessage
    @Environment(\.colorScheme) private var colorScheme
    
    private var backgroundColor: Color {
        if message.isUser {
            return colorScheme == .dark ? .blue : .blue
        } else if message.isError {
            return colorScheme == .dark ? .red.opacity(0.2) : .red.opacity(0.1)
        } else {
            return colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6)
        }
    }
    
    private var textColor: Color {
        if message.isUser {
            return .white
        } else if message.isError {
            return .red
        } else {
            return .primary
        }
    }
    
    var body: some View {
        HStack {
            if message.isUser { Spacer() }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                if !message.isUser || message.isError {
                    HStack {
                        if message.isError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                        } else {
                            Image(systemName: "cpu")
                                .foregroundColor(.secondary)
                        }
                        
                        Text(message.isError ? "Error" : "Assistant")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
                }
                
                Markdown(message.content)
                    .markdownTheme(.gitHub)
                    .foregroundColor(textColor)
                    .font(.body)
                    .padding(12)
                    .background(backgroundColor)
                    .cornerRadius(12)
                    .textSelection(.enabled)
                    .contextMenu {
                        Button(action: {
                            UIPasteboard.general.string = message.content
                        }) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                
                if !message.isUser {
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.8, alignment: message.isUser ? .trailing : .leading)
            
            if !message.isUser { Spacer() }
        }
        .transition(.opacity.combined(with: .move(edge: message.isUser ? .trailing : .leading)))
    }
}

// MARK: - Preview

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = ChatViewModel()
        viewModel.messages = [
            ChatMessage(content: "Hello! How can I help you today?", role: "assistant"),
            ChatMessage(content: "Hi! I'm testing the chat interface.", role: "user"),
            ChatMessage(content: "This is an error message.", role: "assistant", isError: true)
        ]
        
        return NavigationView {
            ChatView(viewModel: viewModel)
                .environmentObject(AppStorageManager.shared)
        }
    }
}
