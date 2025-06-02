//
//  llmChatApp.swift
//  llmChat
//
//  Created by Joshua Impson on 3/7/25.
//

import SwiftUI
import Foundation

// Configure App Transport Security to allow HTTP connections
// This is needed to connect to non-HTTPS endpoints
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Allow all HTTP connections
        URLSession.shared.configuration.waitsForConnectivity = true
        return true
    }
}

@main
struct llmChatApp: App {
    @StateObject private var storage = AppStorageManager.shared
    @State private var selectedTab = 0
    
    init() {
        // Configure appearance
        configureAppearance()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, CoreDataManager.shared.container.viewContext)
                .environmentObject(storage)
        }
    }
    
    private func configureAppearance() {
        // Configure navigation bar appearance
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.systemBackground
        appearance.shadowColor = .clear
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        
        // Fix for iOS 15+ tab bar transparency
        if #available(iOS 15.0, *) {
            let tabBarAppearance = UITabBarAppearance()
            tabBarAppearance.configureWithOpaqueBackground()
            UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        }
    }
}


