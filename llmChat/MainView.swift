import SwiftUI

struct MainView: View {
    @EnvironmentObject var storage: AppStorageManager
    
    var body: some View {
        #if os(iOS)
        // iOS layout - just use the ChatView directly
        ChatView()
            .environmentObject(storage)
        #else
        // macOS layout - use a horizontal split with chat taking more space
        HStack(spacing: 0) {
            // Chat view takes 70% of the space
            ChatView()
                .environmentObject(storage)
                .frame(minWidth: 0, maxWidth: .infinity)
            
            // Settings view takes 30% of the space
            NavigationView {
                SettingsView()
                    .environmentObject(storage)
                    .frame(width: 350)
            }
            .frame(width: 350)
        }
        #endif
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
            .environmentObject(AppStorageManager())
    }
}
