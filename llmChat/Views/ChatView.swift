import SwiftUI
import MarkdownUI

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @EnvironmentObject var storage: AppStorageManager
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showingModelSelector = false
    @State private var showingSettings = false
    @State private var showingClearConfirmation = false
    @State private var scrollToBottomID: UUID?
    
    private let scrollBottomID = UUID()
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
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
                .onChange(of: viewModel.messages) { _ in
                    withAnimation {
                        proxy.scrollTo(scrollBottomID, anchor: .bottom)
                    }
                }
            }
            
            // Input Area
            VStack(spacing: 0) {
                Divider()
                
                // Model selector
                Button(action: { showingModelSelector = true }) {
                    HStack {
                        Image(systemName: "cpu")
                            .imageScale(.small)
                        
                        Text(viewModel.selectedModel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        if viewModel.isLoadingModels {
                            ProgressView()
                                .padding(.leading, 4)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
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
                    
                    // Send Button
                    Button(action: viewModel.sendMessage) {
                        if viewModel.isSending {
                            ProgressView()
                                .padding(8)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundColor(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                                .padding(8)
                        }
                    }
                    .disabled(viewModel.isSending || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                if !viewModel.messages.isEmpty {
                    Button(action: { showingClearConfirmation = true }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationView {
                SettingsView(viewModel: SettingsViewModel())
            }
        }
        .actionSheet(isPresented: $showingModelSelector) {
            ActionSheet(
                title: Text("Select Model"),
                buttons: modelSelectorButtons()
            )
        }
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
    
    private func modelSelectorButtons() -> [ActionSheet.Button] {
        var buttons: [ActionSheet.Button] = viewModel.availableModels.map { model in
                .default(Text(model)) {
                    viewModel.selectedModel = model
                }
        }
        buttons.append(.cancel())
        return buttons
    }
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
