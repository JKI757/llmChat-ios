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
    func saveConversation(
        title: String = "New Conversation", 
        model: String? = nil,
        systemPrompt: String? = nil,
        userPrompt: String? = nil,
        language: String? = nil,
        endpointID: UUID? = nil,
        messages: [ChatMessage], 
        conversationID: UUID? = nil
    ) throws -> UUID? {
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
                } else {
                    // Conversation with ID not found, create new
                    conversation = Conversation(context: context)
                    conversation.id = existingID
                    isNewConversation = true
                }
            } catch {
                // Error fetching, create new
                conversation = Conversation(context: context)
                conversation.id = UUID()
                isNewConversation = true
            }
        } else {
            // No ID provided, create new conversation
            conversation = Conversation(context: context)
            conversation.id = UUID()
            isNewConversation = true
        }
        
        // Update conversation properties
        conversation.timestamp = Date()
        conversation.title = title
        conversation.model = model
        conversation.systemPrompt = systemPrompt
        conversation.userPrompt = userPrompt
        conversation.language = language
        conversation.endpointID = endpointID
        
        // Store messages
        for message in messages {
            let storedMessage = Message(context: context)
            storedMessage.timestamp = message.timestamp
            storedMessage.content = message.content.textValue
            storedMessage.role = message.role
            storedMessage.isError = message.isError
            storedMessage.conversation = conversation
        }
        
        if !isNewConversation {
            // For existing conversations, we need to be more careful
            // First, get existing messages
            let existingMessages = conversation.messages?.allObjects as? [Message] ?? []
            
            // Create a set of message contents we want to keep (since we don't have IDs)
            var messageContentsToKeep = Set<String>()
            
            // Update existing messages and add new ones
            for message in messages {
                let contentValue = message.content.textValue
                let messageKey = contentValue + message.role + message.timestamp.description
                
                if let existingMessage = existingMessages.first(where: { $0.content == contentValue && $0.role == message.role }) {
                    // Update existing message
                    existingMessage.timestamp = message.timestamp
                    existingMessage.content = contentValue
                    existingMessage.role = message.role
                    existingMessage.isError = message.isError
                    messageContentsToKeep.insert(messageKey)
                } else {
                    // Add new message
                    let storedMessage = Message(context: context)
                    storedMessage.timestamp = message.timestamp
                    storedMessage.content = contentValue
                    storedMessage.role = message.role
                    storedMessage.isError = message.isError
                    storedMessage.conversation = conversation
                    messageContentsToKeep.insert(messageKey)
                }
            }
            
            // Remove messages that are no longer needed
            for message in existingMessages {
                let messageKey = message.content + message.role + message.timestamp.description
                if !messageContentsToKeep.contains(messageKey) {
                    context.delete(message)
                }
            }
        }
        
        // Save immediately
        do {
            try context.save()
            print("Successfully saved conversation to Core Data")
        } catch {
            print("Error saving conversation: \(error)")
            throw error
        }
        
        return conversation.id
    }
    
    func fetchConversations() -> [Conversation] {
        let request = NSFetchRequest<Conversation>(entityName: "Conversation")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Conversation.timestamp, ascending: false)]
        
        do {
            return try container.viewContext.fetch(request)
        } catch {
            print("Error fetching conversations: \(error)")
            return []
        }
    }
    
    func deleteConversation(_ conversation: Conversation) {
        container.viewContext.delete(conversation)
        
        do {
            try container.viewContext.save()
        } catch {
            print("Error deleting conversation: \(error)")
        }
    }
    
    func getMessages(for conversation: Conversation) -> [ChatMessage] {
        guard let messages = conversation.messages?.allObjects as? [Message] else {
            return []
        }
        
        return messages.map { message in
            ChatMessage(from: message)
        }.sorted { $0.timestamp < $1.timestamp }
    }
}
