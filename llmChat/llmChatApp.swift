//
//  llmChatApp.swift
//  llmChat
//
//  Created by Joshua Impson on 3/7/25.
//

import SwiftUI

@main
struct llmChatApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
