//
//  AppStorageManager.swift
//  llmChat
//
//  Created by Joshua Impson on 3/7/25.
//

import Foundation

class AppStorageManager: ObservableObject {
    @Published var apiToken: String {
        didSet { UserDefaults.standard.set(apiToken, forKey: "apiToken") }
    }
    
    @Published var apiEndpoint: String {
        didSet { UserDefaults.standard.set(apiEndpoint, forKey: "apiEndpoint") }
    }
    
    @Published var prompt: String {
        didSet { UserDefaults.standard.set(prompt, forKey: "prompt") }
    }
    @Published var preferredLanguage: String {
        didSet { UserDefaults.standard.set(preferredLanguage, forKey: "preferredLanguage") }
    }
    @Published var preferredModel: String {
        didSet { UserDefaults.standard.set(preferredModel, forKey: "preferredModel") }
    }
    @Published var useChatEndpoint: Bool {
        didSet { UserDefaults.standard.set(useChatEndpoint, forKey: "useChatEndpoint") }
    }

    init() {
        self.apiToken = UserDefaults.standard.string(forKey: "apiToken") ?? ""
        self.apiEndpoint = UserDefaults.standard.string(forKey: "apiEndpoint") ?? ""
        self.prompt = UserDefaults.standard.string(forKey: "prompt") ?? "You are a helpful AI assistant."
        self.preferredLanguage = UserDefaults.standard.string(forKey: "preferredLanguage") ?? "English"
        self.preferredModel = UserDefaults.standard.string(forKey: "preferredModel") ?? "gpt-3.5-turbo"
        self.useChatEndpoint = UserDefaults.standard.bool(forKey: "useChatEndpoint")
    }
}
