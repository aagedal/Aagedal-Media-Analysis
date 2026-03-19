import Foundation

enum ChatRole: String, Codable {
    case system
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date
    var imageData: Data?

    init(role: ChatRole, content: String, imageData: Data? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.imageData = imageData
    }
}

struct ChatConversation: Codable {
    var messages: [ChatMessage]
    var fileName: String?
    var contextType: ContextType

    enum ContextType: String, Codable {
        case none
        case metadata
        case transcript
        case analysis
        case all
    }

    init(fileName: String? = nil, contextType: ContextType = .none) {
        self.messages = []
        self.fileName = fileName
        self.contextType = contextType
    }

    mutating func addMessage(_ message: ChatMessage) {
        messages.append(message)
    }
}
