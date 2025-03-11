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
struct LLMChatApp: App {
    // Create a shared instance of AppStorageManager
    @StateObject private var storageManager = AppStorageManager()
    
    // Register the app delegate
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // This is a workaround to allow HTTP connections
        if let urlSessionConfig = URLSessionConfiguration.default.value(forKey: "_networkServiceType") {
            URLSessionConfiguration.default.httpShouldSetCookies = true
            URLSessionConfiguration.default.httpCookieAcceptPolicy = .always
            URLSessionConfiguration.default.httpMaximumConnectionsPerHost = 10
            print("URLSession configured to allow HTTP connections")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ChatView()
                .environmentObject(storageManager)
        }
    }
}
