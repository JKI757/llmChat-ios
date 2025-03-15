import SwiftUI

struct PromptsView: View {
    @StateObject private var storage = AppStorageManager()
    @State private var isAddingPrompt = false
    @State private var isEditingPrompt = false
    @State private var editingPromptID: UUID?
    @State private var promptName = ""
    @State private var systemPrompt = ""
    @State private var userPrompt = ""
    
    var body: some View {
        List {
            ForEach(storage.savedPrompts) { prompt in
                promptRowView(for: prompt)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Select the prompt when tapped
                        storage.selectPrompt(id: prompt.id)
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deletePrompt(prompt)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .navigationTitle("Prompt Library")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    promptName = ""
                    systemPrompt = ""
                    userPrompt = ""
                    isAddingPrompt = true
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingPrompt) {
            addPromptView()
        }
        .sheet(isPresented: $isEditingPrompt) {
            editPromptView()
        }
    }
    
    // MARK: - Helper Views
    
    private func promptRowView(for prompt: SavedPrompt) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(prompt.name)
                        .font(.headline)
                    
                    // Show a subtle indicator for the currently selected prompt
                    if isCurrentlySelected(prompt) {
                        Text("(Active)")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .padding(.leading, 4)
                    }
                }
                
                Text("System: " + prompt.systemPrompt.prefix(60))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                
                if !prompt.userPrompt.isEmpty {
                    Text("User: " + prompt.userPrompt.prefix(60))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                // Edit button
                Button(action: {
                    prepareForEditing(prompt)
                }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
                .buttonStyle(BorderlessButtonStyle())
                
                // Star button for setting default prompt
                Button(action: {
                    storage.setDefaultPrompt(id: prompt.id)
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                }) {
                    Image(systemName: storage.defaultPromptID == prompt.id ? "star.fill" : "star")
                        .foregroundColor(.yellow)
                        .font(.title3)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(.vertical, 4)
        .background(
            isCurrentlySelected(prompt) ? 
                Color.accentColor.opacity(0.1) : 
                Color.clear
        )
        .cornerRadius(8)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deletePrompt(prompt)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    // Helper method to check if a prompt is currently selected
    private func isCurrentlySelected(_ prompt: SavedPrompt) -> Bool {
        return storage.systemPrompt == prompt.systemPrompt &&
               storage.userPrompt == prompt.userPrompt
    }
    
    private func addPromptView() -> some View {
        NavigationView {
            Form {
                Section(header: Text("Prompt Nickname"), footer: Text("A short, descriptive name for this prompt")) {
                    TextField("Name", text: $promptName)
                }
                
                Section(header: Text("System Prompt"), footer: Text("Instructions that define the assistant's behavior")) {
                    TextEditor(text: $systemPrompt)
                        .frame(minHeight: 100)
                }
                
                Section(header: Text("User Prompt (Optional)"), footer: Text("Text that will be prepended to your messages")) {
                    TextEditor(text: $userPrompt)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Add New Prompt")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isAddingPrompt = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        saveNewPrompt()
                    }
                    .disabled(promptName.isEmpty || systemPrompt.isEmpty)
                }
            }
        }
    }
    
    private func editPromptView() -> some View {
        NavigationView {
            Form {
                Section(header: Text("Prompt Nickname"), footer: Text("A short, descriptive name for this prompt")) {
                    TextField("Name", text: $promptName)
                }
                
                Section(header: Text("System Prompt"), footer: Text("Instructions that define the assistant's behavior")) {
                    TextEditor(text: $systemPrompt)
                        .frame(minHeight: 100)
                }
                
                Section(header: Text("User Prompt (Optional)"), footer: Text("Text that will be prepended to your messages")) {
                    TextEditor(text: $userPrompt)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Edit Prompt")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isEditingPrompt = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveEditedPrompt()
                    }
                    .disabled(promptName.isEmpty || systemPrompt.isEmpty)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func prepareForEditing(_ prompt: SavedPrompt) {
        editingPromptID = prompt.id
        promptName = prompt.name
        systemPrompt = prompt.systemPrompt
        userPrompt = prompt.userPrompt
        isEditingPrompt = true
    }
    
    private func saveNewPrompt() {
        storage.addPrompt(name: promptName, systemPrompt: systemPrompt, userPrompt: userPrompt)
        isAddingPrompt = false
    }
    
    private func saveEditedPrompt() {
        if let id = editingPromptID {
            storage.updatePrompt(id: id, name: promptName, systemPrompt: systemPrompt, userPrompt: userPrompt)
        }
        isEditingPrompt = false
    }
    
    private func deletePrompt(_ prompt: SavedPrompt) {
        if let index = storage.savedPrompts.firstIndex(where: { $0.id == prompt.id }) {
            storage.deletePrompt(at: IndexSet(integer: index))
        }
    }
}

struct PromptsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PromptsView()
        }
    }
}
