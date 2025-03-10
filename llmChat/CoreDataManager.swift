import Foundation
import CoreData

class CoreDataManager {
    static let shared = CoreDataManager()
    let container: NSPersistentContainer
    
    private init() {
        container = NSPersistentContainer(name: "ChatHistory")
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                print("Failed to load Core Data: \(error), \(error.userInfo)")
            }
        }
    }
    
    var context: NSManagedObjectContext {
        return container.viewContext
    }

    @discardableResult
    func saveConversation(model: String, prompt: String, language: String, messages: [ChatMessage], apiToken: String = "", apiEndpoint: String = "", conversationID: UUID? = nil) -> UUID? {
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
        conversation.prompt = prompt
        conversation.language = language
        
        if let encodedMessages = try? JSONEncoder().encode(messages) {
            conversation.messages = encodedMessages
        } else {
            conversation.messages = nil
        }
        
        // Save immediately
        do {
            try context.save()
        } catch {
            print("Failed to save conversation: \(error)")
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
                model: model
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
        
        do {
            return try context.fetch(request)
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
