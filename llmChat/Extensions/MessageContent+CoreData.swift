import Foundation

extension MessageContent {
    // Helper function to convert MessageContent to a String for CoreData storage
    var stringValue: String {
        switch self {
        case .text(let text):
            return text
        case .image(_):
            return "[Image]" // We don't store the actual image data in CoreData to save space
        }
    }
}
