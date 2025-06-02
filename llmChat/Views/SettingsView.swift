import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @EnvironmentObject var storage: AppStorageManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            // User Section
            Section(header: Text("Profile")) {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Your Name", text: $viewModel.userName)
                            .font(.headline)
                        
                        Text("Free Plan")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .padding(.leading, 8)
                }
                .padding(.vertical, 8)
            }
            
            // App Settings Section
            Section(header: Text("Appearance")) {
                Picker("Theme", selection: $viewModel.appearance) {
                    ForEach(0..<viewModel.appearanceModes.count, id: \.self) { index in
                        Text(viewModel.appearanceModes[index]).tag(index)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.vertical, 4)
                
                Toggle("Enable Haptics", isOn: $viewModel.hapticsEnabled)
                Toggle("Send Analytics", isOn: $viewModel.analyticsEnabled)
            }
            
            // Endpoints Section
            Section(header: Text("Endpoints")) {
                NavigationLink(destination: EndpointsView(storage: storage)) {
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundColor(.blue)
                        Text("Manage Endpoints")
                        Spacer()
                        if let defaultID = storage.defaultEndpointID,
                           let endpoint = storage.savedEndpoints.first(where: { $0.id == defaultID }) {
                            Text(endpoint.name)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Support Section
            Section(header: Text("Support")) {
                Button(action: viewModel.sendFeedback) {
                    SettingsRow(icon: "envelope", title: "Send Feedback", color: .blue)
                }
                .foregroundColor(.primary)
                
                Button(action: viewModel.rateApp) {
                    SettingsRow(icon: "star", title: "Rate the App", color: .yellow)
                }
                .foregroundColor(.primary)
                
                Button(action: viewModel.shareApp) {
                    SettingsRow(icon: "square.and.arrow.up", title: "Share with Friends", color: .green)
                }
                .foregroundColor(.primary)
            }
            
            // About Section
            Section(header: Text("About")) {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("\(viewModel.appVersion) (\(viewModel.buildNumber))")
                        .foregroundColor(.secondary)
                }
                
                Link(destination: URL(string: "https://github.com/yourusername/llmchat")!) {
                    SettingsRow(icon: "chevron.left.forwardslash.chevron.right", title: "Source Code", color: .purple)
                }
                
                Link(destination: URL(string: "https://github.com/yourusername/llmchat/blob/main/PRIVACY.md")!) {
                    SettingsRow(icon: "hand.raised", title: "Privacy Policy", color: .blue)
                }
                
                Link(destination: URL(string: "https://github.com/yourusername/llmchat/blob/main/TERMS.md")!) {
                    SettingsRow(icon: "doc.text", title: "Terms of Service", color: .gray)
                }
            }
            
            // Credits Section
            Section {
                VStack(alignment: .center, spacing: 8) {
                    Text("Made with ❤️ by Your Name")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 20) {
                        Button(action: viewModel.openTwitter) {
                            Image(systemName: "bird")
                                .font(.title3)
                                .foregroundColor(.blue)
                        }
                        
                        Button(action: viewModel.openGitHub) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.title3)
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Settings Row View

struct SettingsRow: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24, height: 24)
                .foregroundColor(color)
            
            Text(title)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let storage = AppStorageManager.shared
        storage.savedEndpoints = [
            SavedEndpoint(
                name: "OpenAI",
                url: "https://api.openai.com",
                defaultModel: "gpt-3.5-turbo",
                requiresAuth: true,
                endpointType: .openAI,
                isChatEndpoint: true
            )
        ]
        storage.defaultEndpointID = storage.savedEndpoints[0].id
        
        return NavigationView {
            SettingsView(viewModel: SettingsViewModel())
                .environmentObject(storage)
        }
    }
}
