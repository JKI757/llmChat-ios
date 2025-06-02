import SwiftUI

struct PromptsView: View {
    @EnvironmentObject var storage: AppStorageManager
    @State private var showingAddPrompt = false
    @State private var editingPrompt: SavedPrompt?
    
    var body: some View {
        List {
            Section(header: Text("Saved Prompts")) {
                if storage.savedPrompts.isEmpty {
                    Text("No prompts yet. Tap + to create one.")
                        .foregroundColor(.secondary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach(storage.savedPrompts.sorted(by: { $0.name < $1.name })) { prompt in
                        PromptRow(prompt: prompt)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingPrompt = prompt
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    if let index = storage.savedPrompts.firstIndex(where: { $0.id == prompt.id }) {
                                        storage.deletePrompts(at: IndexSet(integer: index))
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                
                                Button {
                                    editingPrompt = prompt
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    storage.defaultPromptID = prompt.id
                                    storage.saveDefaultPromptID()
                                } label: {
                                    Label("Set Default", systemImage: "star")
                                }
                                .tint(.yellow)
                            }
                    }
                }
            }
        }
        .navigationTitle("Prompt Library")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingAddPrompt = true
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddPrompt) {
            PromptFormView(mode: .add)
        }
        .sheet(item: $editingPrompt) { prompt in
            PromptFormView(mode: .edit(prompt))
        }
    }
}

struct PromptRow: View {
    let prompt: SavedPrompt
    @EnvironmentObject var storage: AppStorageManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Leading checkmark for default prompt
            if storage.defaultPromptID == prompt.id {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14, weight: .bold))
            } else {
                // Empty space to maintain alignment
                Image(systemName: "checkmark")
                    .foregroundColor(.clear)
                    .font(.system(size: 14))
            }
            
            // Prompt content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(prompt.name)
                        .font(.headline)
                    
                    Spacer()
                    
                    if storage.defaultPromptID == prompt.id {
                        Text("Default")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                
                if !prompt.systemPrompt.isEmpty {
                    Text("System: \(prompt.systemPrompt)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                if !prompt.userPrompt.isEmpty {
                    Text("User: \(prompt.userPrompt)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct PromptFormView: View {
    enum Mode {
        case add
        case edit(SavedPrompt)
    }
    
    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var storage: AppStorageManager
    
    @State private var name = ""
    @State private var systemPrompt = ""
    @State private var userPrompt = ""
    
    var isEditMode: Bool {
        switch mode {
        case .add: return false
        case .edit: return true
        }
    }
    
    var title: String {
        isEditMode ? "Edit Prompt" : "New Prompt"
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Prompt Details")) {
                    TextField("Prompt Name", text: $name)
                        .autocapitalization(.words)
                        .disableAutocorrection(false)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("System Prompt")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text("Required")
                                .font(.caption2)
                                .foregroundColor(systemPrompt.isEmpty ? .red : .secondary)
                        }
                        
                        ZStack(alignment: .topLeading) {
                            if systemPrompt.isEmpty {
                                Text("Define the AI's behavior and capabilities...")
                                    .foregroundColor(Color(.placeholderText))
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            
                            TextEditor(text: $systemPrompt)
                                .frame(minHeight: 120)
                                .padding(4)
                                .background(Color(UIColor.systemGray6))
                                .cornerRadius(8)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("User Prompt")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text("Optional")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        ZStack(alignment: .topLeading) {
                            if userPrompt.isEmpty {
                                Text("Text to prepend to your first message...")
                                    .foregroundColor(Color(.placeholderText))
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            
                            TextEditor(text: $userPrompt)
                                .frame(minHeight: 100)
                                .padding(4)
                                .background(Color(UIColor.systemGray6))
                                .cornerRadius(8)
                        }
                    }
                }
                
                Section {
                    Button(action: savePrompt) {
                        Text(isEditMode ? "Update Prompt" : "Save Prompt")
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 4)
                            .foregroundColor(.white)
                            .background(name.isEmpty || systemPrompt.isEmpty ? Color.gray : Color.accentColor)
                            .cornerRadius(8)
                    }
                    .disabled(name.isEmpty || systemPrompt.isEmpty)
                    .buttonStyle(PlainButtonStyle())
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("System Prompt: Defines the AI's behavior, personality, and capabilities.")
                        
                        Text("User Prompt: Optional text that will be automatically prepended to your first message in each conversation.")
                        
                        if !isEditMode && storage.savedPrompts.isEmpty {
                            Text("Tip: After creating a prompt, you can set it as the default in Settings or select it for individual chats.")
                                .italic()
                                .padding(.top, 4)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                setupInitialValues()
            }
        }
    }
    
    private func setupInitialValues() {
        switch mode {
        case .add:
            break
        case .edit(let prompt):
            name = prompt.name
            systemPrompt = prompt.systemPrompt
            userPrompt = prompt.userPrompt
        }
    }
    
    private func savePrompt() {
        switch mode {
        case .add:
            storage.addPrompt(name: name, systemPrompt: systemPrompt, userPrompt: userPrompt)
        case .edit(let prompt):
            storage.updatePrompt(id: prompt.id, name: name, systemPrompt: systemPrompt, userPrompt: userPrompt)
        }
        dismiss()
    }
}

struct PromptsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PromptsView()
                .environmentObject(AppStorageManager.shared)
        }
    }
}
