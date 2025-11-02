import Foundation

struct Memory: Identifiable, Codable {
    let id: UUID
    let fact: String
    let tags: [String]
    let extractedAt: Date
    let importance: Int // 1-5, higher = more important
    
    init(id: UUID = UUID(),
         fact: String,
         tags: [String],
         extractedAt: Date = Date(),
         importance: Int) {
        self.id = id
        self.fact = fact
        self.tags = tags.map { $0.lowercased() } // normalize tags
        self.extractedAt = extractedAt
        self.importance = min(max(importance, 1), 5) // clamp between 1-5
    }
}

// For the extraction response from Gemini
struct ExtractedMemory: Codable {
    let fact: String
    let tags: [String]
    let importance: Int
}

struct MemoryExtractionResponse: Codable {
    let memories: [ExtractedMemory]
}
