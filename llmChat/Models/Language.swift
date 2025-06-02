import Foundation

/// Represents supported languages for the app
enum Language: String, CaseIterable, Identifiable, Codable {
    case system = "System"
    case english = "English"
    case spanish = "Spanish"
    case french = "French"
    case german = "German"
    case italian = "Italian"
    case portuguese = "Portuguese"
    case russian = "Russian"
    case japanese = "Japanese"
    case chinese = "Chinese"
    case korean = "Korean"
    
    var id: String { rawValue }
    
    /// Returns a localized description of the language
    var localizedName: String {
        switch self {
        case .system:
            return "System Default"
        default:
            return rawValue
        }
    }
    
    /// Returns a prompt instruction for the AI to respond in this language
    var promptInstruction: String? {
        switch self {
        case .system:
            return nil
        case .english:
            return "Please respond in English."
        case .spanish:
            return "Por favor, responde en español."
        case .french:
            return "Veuillez répondre en français."
        case .german:
            return "Bitte antworten Sie auf Deutsch."
        case .italian:
            return "Per favore, rispondi in italiano."
        case .portuguese:
            return "Por favor, responda em português."
        case .russian:
            return "Пожалуйста, ответьте на русском языке."
        case .japanese:
            return "日本語で回答してください。"
        case .chinese:
            return "请用中文回答。"
        case .korean:
            return "한국어로 대답해 주세요."
        }
    }
}
