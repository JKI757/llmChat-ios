import SwiftUI

struct PromptsView: View {
    @StateObject private var storage = AppStorageManager()
    @State private var isAddingPrompt = false
    @State private var isEditingPrompt = false
    @State private var editingPromptID: UUID?
    @State private var promptName = ""
    @State private var promptContent = ""
    
    var body: some View {
        List {
            ForEach(storage.savedPrompts) { prompt in
                VStack(alignment: .leading, spacing: 8) {
                    Text(prompt.name)
                        .font(.headline)
                    
                    Text(prompt.content)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Select this prompt and update the current prompt
                    storage.selectPrompt(id: prompt.id)
                    // Show a confirmation
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
                .contextMenu {
                    Button(action: {
                        editingPromptID = prompt.id
                        promptName = prompt.name
                        promptContent = prompt.content
                        isEditingPrompt = true
                    }) {
                        Label("Edit", systemImage: "pencil")
                    }
                }
            }
            .onDelete(perform: storage.deletePrompt)
        }
        .navigationTitle("Prompt Library")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    promptName = ""
                    promptContent = ""
                    isAddingPrompt = true
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingPrompt) {
            promptEditorView(title: "Add New Prompt", buttonTitle: "Add") {
                storage.addPrompt(name: promptName, content: promptContent)
                isAddingPrompt = false
            }
        }
        .sheet(isPresented: $isEditingPrompt) {
            promptEditorView(title: "Edit Prompt", buttonTitle: "Save") {
                if let id = editingPromptID {
                    storage.updatePrompt(id: id, name: promptName, content: promptContent)
                }
                isEditingPrompt = false
            }
        }
    }
    
    private func promptEditorView(title: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        NavigationView {
            Form {
                Section(header: Text("Prompt Details")) {
                    TextField("Name", text: $promptName)
                    
                    TextEditor(text: $promptContent)
                        .frame(minHeight: 150)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isAddingPrompt = false
                        isEditingPrompt = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(buttonTitle) {
                        action()
                    }
                    .disabled(promptName.isEmpty || promptContent.isEmpty)
                }
            }
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
