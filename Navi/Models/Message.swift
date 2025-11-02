import Foundation

struct Message: Identifiable, Codable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date
    let companion: Companion?
    
    init(id: UUID = UUID(), content: String, isUser: Bool, timestamp: Date = Date(), companion: Companion? = nil) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
        self.companion = companion
    }
}
