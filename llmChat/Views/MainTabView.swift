import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var settingsViewModel = SettingsViewModel()
    @EnvironmentObject private var appStorage: AppStorageManager
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView {
                ChatView(viewModel: chatViewModel)
            }
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
            }
            .tag(0)
            
            NavigationView {
                ConversationHistoryView()
                    .environment(\.managedObjectContext, CoreDataManager.shared.container.viewContext)
            }
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .tag(1)
            
            NavigationView {
                SettingsView(viewModel: settingsViewModel)
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(2)
        }
        .accentColor(.blue)
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(AppStorageManager.shared)
            .environment(\.managedObjectContext, CoreDataManager.shared.container.viewContext)
    }
}
