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

    func saveConversation(model: String, prompt: String, language: String, messages: [ChatMessage]) {
        // Ensure that the Conversation NSManagedObject subclass is generated from your data model.
        let conversation = Conversation(context: context)
        conversation.id = UUID()
        conversation.timestamp = Date()
        conversation.model = model
        conversation.prompt = prompt
        conversation.language = language
        
        if let encodedMessages = try? JSONEncoder().encode(messages) {
            conversation.messages = encodedMessages
        } else {
            conversation.messages = nil
        }
        
        do {
            try context.save()
        } catch {
            print("Failed to save conversation: \(error)")
        }
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
