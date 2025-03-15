import Foundation
import CoreData

class CoreDataManager {
    static let shared = CoreDataManager()
    let container: NSPersistentContainer
    
    private init() {
        container = NSPersistentContainer(name: "ChatHistory")
        
        // Add options to handle migration failures more gracefully
        container.persistentStoreDescriptions.forEach { description in
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Handle the error
                print("Failed to load Core Data: \(error), \(error.userInfo)")
                
                // If there's a store URL, try to remove it and recreate
                if let storeURL = storeDescription.url {
                    do {
                        try FileManager.default.removeItem(at: storeURL)
                        print("Removed corrupted store at \(storeURL)")
                        
                        // Try to load again with the store removed
                        self.container.loadPersistentStores(completionHandler: { (_, loadError) in
                            if let loadError = loadError {
                                print("Still failed to load after removing store: \(loadError)")
                            } else {
                                print("Successfully reloaded store after removing corrupted one")
                            }
                        })
                    } catch {
                        print("Failed to remove corrupted store: \(error)")
                    }
                }
            }
        })
        
        // Configure the context to merge policy that favors in-memory changes
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
    
    var context: NSManagedObjectContext {
        return container.viewContext
    }

    @discardableResult
    func saveConversation(model: String, systemPrompt: String, userPrompt: String = "", language: String, messages: [ChatMessage], apiToken: String = "", apiEndpoint: String = "", conversationID: UUID? = nil) throws -> UUID? {
        // For backward compatibility
        let prompt = systemPrompt
        // Check if we're updating an existing conversation or creating a new one
        let conversation: Conversation
        let isNewConversation: Bool
        
        if let existingID = conversationID {
            // Try to find the existing conversation
            let request: NSFetchRequest<Conversation> = Conversation.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", existingID as CVarArg)
            
            do {
                let results = try context.fetch(request)
                if let existingConversation = results.first {
                    // Update existing conversation
                    conversation = existingConversation
                    isNewConversation = false
                    print("Updating existing conversation: \(existingID)")
                } else {
                    // Conversation with ID not found, create new
                    conversation = Conversation(context: context)
                    conversation.id = existingID
                    isNewConversation = true
                    print("Creating new conversation with specified ID: \(existingID)")
                }
            } catch {
                // Error fetching, create new
                conversation = Conversation(context: context)
                conversation.id = UUID()
                isNewConversation = true
                print("Error fetching conversation, creating new: \(error)")
            }
        } else {
            // No ID provided, create new conversation
            conversation = Conversation(context: context)
            conversation.id = UUID()
            isNewConversation = true
            print("Creating new conversation with new ID")
        }
        
        // Always update timestamp when saving
        conversation.timestamp = Date()
        conversation.model = model
        conversation.systemPrompt = systemPrompt
        conversation.language = language
        
        // Store system prompt and user prompt separately
        conversation.systemPrompt = systemPrompt
        conversation.userPrompt = userPrompt.isEmpty ? nil : userPrompt
        
        if let encodedMessages = try? JSONEncoder().encode(messages) {
            conversation.messages = encodedMessages
        } else {
            conversation.messages = nil
        }
        
        // Save immediately
        do {
            try context.save()
            print("Successfully saved conversation to Core Data")
        } catch {
            print("Failed to save conversation: \(error)")
            throw error
        }
        
        // Only generate a new title if this is a new conversation or if we have a significant update
        // (e.g., more than 2 new messages since last save)
        let shouldUpdateTitle = isNewConversation || messages.count > 2
        
        if shouldUpdateTitle {
            // Generate a title using LLM if possible
            LLMService.generateConversationSummary(
                messages: messages,
                apiToken: apiToken,
                endpoint: apiEndpoint,
                model: model,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt
            ) { [weak self] title in
                guard let self = self else { return }
                
                // Store the title in UserDefaults
                let titleKey = "conversation_title_\(conversation.id?.uuidString ?? UUID().uuidString)"
                UserDefaults.standard.set(title, forKey: titleKey)
                print("Saved conversation title to UserDefaults: \(title)")
            }
        }
        
        // Return the ID for tracking
        return conversation.id
    }

    func fetchConversations() -> [Conversation] {
        let request: NSFetchRequest<Conversation> = Conversation.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        // Ensure we're getting fresh data
        context.refreshAllObjects()
        
        do {
            let results = try context.fetch(request)
            print("Fetched \(results.count) conversations from Core Data")
            return results
        } catch {
            print("Failed to fetch conversations: \(error)")
            return []
        }
    }

    func deleteConversation(_ conversation: Conversation) {
        context.delete(conversation)
        do {
            try context.save()
        } catch {
            print("Failed to delete conversation: \(error)")
        }
    }
}
