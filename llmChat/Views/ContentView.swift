//
//  ContentView.swift
//  llmChat
//
//  Created by Joshua Impson on 3/7/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var appStorage = AppStorageManager.shared
    
    var body: some View {
        MainTabView()
            .environmentObject(appStorage)
            .onAppear {
                // Initialize default endpoints if none exist
                if appStorage.savedEndpoints.isEmpty {
                    appStorage.initializeDefaultEndpoints()
                }
            }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
