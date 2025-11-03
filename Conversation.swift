import Foundation

struct Conversation: Identifiable, Codable {
    let id: UUID
    var messages: [Message]
    var companion: Companion
    let startedAt: Date
    var lastUpdated: Date
    var summary: String?
    
    init(id: UUID = UUID(), companion: Companion, messages: [Message] = [], startedAt: Date = Date()) {
        self.id = id
        self.companion = companion
        self.messages = messages
        self.startedAt = startedAt
        self.lastUpdated = startedAt
        self.summary = nil
    }
    
    mutating func addMessage(_ message: Message) {
        messages.append(message)
        lastUpdated = Date()
    }
    
    func getRecentMessages(count: Int = 10) -> [Message] {
        return Array(messages.suffix(count))
    }
}
