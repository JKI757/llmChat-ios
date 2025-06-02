import Foundation
import CoreData

extension Message {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Message> {
        return NSFetchRequest<Message>(entityName: "Message")
    }

    @NSManaged public var content: String
    @NSManaged public var role: String
    @NSManaged public var timestamp: Date
    @NSManaged public var isError: Bool
    @NSManaged public var conversation: Conversation?
}
