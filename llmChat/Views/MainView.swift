import SwiftUI

struct MainView: View {
    @EnvironmentObject var storage: AppStorageManager
    @StateObject private var chatViewModel = ChatViewModel()
    
    var body: some View {
        #if os(iOS)
        // iOS layout - just use the ChatView directly
        ChatView(viewModel: chatViewModel)
            .environmentObject(storage)
        #else
        // macOS layout - use a horizontal split with chat taking 2/3 of the space
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Chat view takes 2/3 of the space
                ChatView(viewModel: chatViewModel)
                    .environmentObject(storage)
                    .frame(width: geometry.size.width * 0.67)
                
                // Settings view takes 1/3 of the space
                NavigationView {
                    SettingsView(viewModel: SettingsViewModel())
                        .environmentObject(storage)
                }
                .frame(width: geometry.size.width * 0.33)
            }
        }
        #endif
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
            .environmentObject(AppStorageManager.shared)
    }
}
