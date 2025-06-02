import Foundation
import CoreData

extension Conversation {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Conversation> {
        return NSFetchRequest<Conversation>(entityName: "Conversation")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var timestamp: Date?
    @NSManaged public var title: String?
    @NSManaged public var model: String?
    @NSManaged public var systemPrompt: String?
    @NSManaged public var userPrompt: String?
    @NSManaged public var language: String?
    @NSManaged public var endpointID: UUID?
    @NSManaged public var messages: NSSet?
}

// MARK: Generated accessors for messages
extension Conversation {
    @objc(addMessagesObject:)
    @NSManaged public func addToMessages(_ value: Message)
    
    @objc(removeMessagesObject:)
    @NSManaged public func removeFromMessages(_ value: Message)
    
    @objc(addMessages:)
    @NSManaged public func addToMessages(_ values: NSSet)
    
    @objc(removeMessages:)
    @NSManaged public func removeFromMessages(_ values: NSSet)
}
