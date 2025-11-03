import Foundation

class MemoryService {
    private let geminiService: GeminiLiveService
    private let storageService: StorageService
    
    init(geminiService: GeminiLiveService, storageService: StorageService) {
        self.geminiService = geminiService
        self.storageService = storageService
    }
    
    // MARK: - Context Building
    
    /// Build context for sending with each message
    func buildContext(for conversation: Conversation, currentMessage: String) -> String {
        var context = ""
        
        // Load global memories
        let globalMemories = storageService.loadGlobalMemories()
        
        // 1. Add conversation summary if it exists
        if let summary = conversation.summary, !summary.isEmpty {
            context += "CONVERSATION SUMMARY:\n\(summary)\n\n"
        }
        
        // 2. Find and add relevant memories
        let relevantMemories = findRelevantMemories(
            for: currentMessage,
            in: globalMemories,
            limit: 5
        )
        
        if !relevantMemories.isEmpty {
            context += "RELEVANT FACTS YOU SHOULD KNOW:\n"
            for memory in relevantMemories {
                context += "- \(memory.fact)\n"
                
                // Add psychological context if present
                if let insight = memory.psychologicalInsight {
                    if let pattern = insight.patternType {
                        context += "  (Pattern: \(pattern.rawValue))\n"
                    }
                    if let distortion = insight.cognitiveDistortion {
                        context += "  (Distortion: \(distortion.rawValue))\n"
                    }
                    if let technique = insight.effectiveTechnique {
                        context += "  (What helps: \(technique))\n"
                    }
                    if let trigger = insight.triggerIdentified {
                        context += "  (Trigger: \(trigger))\n"
                    }
                }
            }
            context += "\n"
        }
        
        return context
    }
    
    // MARK: - Memory Extraction
    
    /// Extract facts from recent conversation and return new/updated memories
    func extractAndStoreMemories(from conversation: Conversation, recentMessages: [Message]) async throws -> (newMemories: [Memory], updatedMemories: [(old: Memory, new: Memory)]) {
        // Only extract if there are enough new messages
        guard recentMessages.count >= 4 else { return ([], []) }
        
        // Build conversation text for extraction
        let conversationText = recentMessages.map { message in
            let role = message.isUser ? "User" : conversation.companion.rawValue
            return "\(role): \(message.content)"
        }.joined(separator: "\n")
        
        // Create extraction prompt
        let extractionPrompt = """
        Analyze this conversation and extract important facts that should be remembered long-term.
        
        Focus on:
        - Personal details (name, job, location, age, etc.)
        - Important people/pets (names, relationships)
        - Recurring issues or concerns
        - **Triggers** (what causes stress/anxiety/distress)
        - **Coping strategies** (what helps or doesn't help)
        - **Cognitive patterns** (catastrophizing, black-and-white thinking, etc.)
        - **Emotional patterns** (recurring anxiety, depression, anger)
        - **Effective techniques** (grounding, breathing, specific interventions that worked)
        - Goals and aspirations
        - Significant life events
        
        Conversation:
        \(conversationText)
        
        Return ONLY a JSON object with this exact structure (no markdown, no explanations):
        {
          "memories": [
            {
              "fact": "Clear, specific statement of the fact",
              "category": "general|preferences|relationships|work|health|goals|triggers|copingStrategies|psychologicalPattern",
              "tags": ["relevant", "searchable", "keywords"],
              "importance": 1-10,
              "psychological_insight": {
                "pattern_type": "recurringAnxiety|depressiveEpisodes|angerOutbursts|avoidanceBehavior|catastrophizingPattern|perfectionism|socialWithdrawal|workStress|academicPressure|null",
                "cognitive_distortion": "catastrophizing|blackAndWhiteThinking|overgeneralization|mindReading|fortuneTelling|emotionalReasoning|shouldStatements|labeling|personalization|mentalFilter|discountingPositives|null",
                "effective_technique": "Name of technique that helped (e.g., '5-4-3-2-1 grounding', 'box breathing', 'thought challenging')|null",
                "trigger_identified": "Specific trigger (e.g., 'exams', 'work deadlines', 'social situations')|null"
              }
            }
          ]
        }
        
        CRITICAL RULES TO PREVENT FALSE MEMORIES:
        - ONLY extract facts that the USER explicitly stated themselves
        - DO NOT extract information that the AI companion guessed, assumed, or suggested
        - DO NOT extract questions the AI asked
        - If the AI mentioned something but the user didn't confirm it, DO NOT extract it
        - When in doubt, DO NOT extract - it's better to miss a memory than store a false one
        
        PSYCHOLOGICAL PATTERN EXTRACTION:
        - If user says "I always think the worst will happen" → extract catastrophizing pattern
        - If companion suggests a technique and user says it helped → extract as effective_technique
        - If user mentions "exams make me anxious" → extract "exams" as trigger
        - If user shows black-and-white thinking ("I'm either perfect or a failure") → extract distortion
        - Only extract psychological insights when explicitly demonstrated in conversation
        
        Additional Rules:
        - Only extract genuinely important facts worth remembering long-term
        - Be specific (not "user has anxiety" but "user experiences test anxiety before exams")
        - Tags should be lowercase, single words or hyphenated phrases for search
        - Importance: 1=minor detail, 5=notable, 10=critical information
        - psychological_insight fields can be null if not applicable
        - If nothing important to extract, return empty array
        - DO NOT include any text outside the JSON object
        
        Examples:
        
        User: "I get so anxious before exams, I always think I'll fail"
        Extract: 
        {
          "fact": "User experiences test anxiety and catastrophizes about exam performance",
          "category": "psychologicalPattern",
          "tags": ["anxiety", "exams", "catastrophizing", "academic"],
          "importance": 7,
          "psychological_insight": {
            "pattern_type": "academicPressure",
            "cognitive_distortion": "catastrophizing",
            "effective_technique": null,
            "trigger_identified": "exams"
          }
        }
        
        User: "That grounding exercise you suggested really helped calm me down"
        Extract:
        {
          "fact": "5-4-3-2-1 grounding technique helps user manage anxiety",
          "category": "copingStrategies",
          "tags": ["grounding", "anxiety", "technique", "effective"],
          "importance": 8,
          "psychological_insight": {
            "pattern_type": null,
            "cognitive_distortion": null,
            "effective_technique": "5-4-3-2-1 grounding",
            "trigger_identified": null
          }
        }
        """
        
        // Use Gemini to extract
        let extractedJSON = try await callGeminiForExtraction(prompt: extractionPrompt)
        
        // Parse the response
        guard let data = extractedJSON.data(using: .utf8),
              let response = try? JSONDecoder().decode(MemoryExtractionResponse.self, from: data) else {
            print(">>> [ERROR] Failed to parse memory extraction response")
            return ([], [])
        }
        
        // Load existing global memories
        let existingMemories = storageService.loadGlobalMemories()
        
        // Load blacklisted memories
        let blacklistedMemories = storageService.loadBlacklistedMemories()
        
        // Convert to Memory objects
        let newMemories = response.memories.map { extracted in
            let category = MemoryCategory(rawValue: extracted.category) ?? .general
            
            // Convert psychological insight if present
            var psychInsight: PsychologicalInsight? = nil
            if let extractedInsight = extracted.psychologicalInsight {
                let patternType = extractedInsight.patternType.flatMap { PatternType(rawValue: $0) }
                let distortion = extractedInsight.cognitiveDistortion.flatMap { CognitiveDistortion(rawValue: $0) }
                
                psychInsight = PsychologicalInsight(
                    patternType: patternType,
                    cognitiveDistortion: distortion,
                    effectiveTechnique: extractedInsight.effectiveTechnique,
                    triggerIdentified: extractedInsight.triggerIdentified
                )
            }
            
            return Memory(
                fact: extracted.fact,
                category: category,
                importance: extracted.importance,
                tags: extracted.tags,
                psychologicalInsight: psychInsight
            )
        }
        
        // Process memories: filter blacklisted, update conflicts, or add new ones
        var uniqueMemories: [Memory] = []
        var memoriesToUpdate: [(old: Memory, new: Memory)] = []
        
        for newMemory in newMemories {
            // Check if blacklisted
            if isBlacklisted(newMemory, in: blacklistedMemories) {
                print(">>> [MEMORY] Skipped blacklisted memory: \(newMemory.fact)")
                continue
            }
            
            // Check for conflicts/updates
            if let conflictingMemory = findConflictingMemory(newMemory, in: existingMemories) {
                memoriesToUpdate.append((old: conflictingMemory, new: newMemory))
                print(">>> [MEMORY] Updated: '\(conflictingMemory.fact)' → '\(newMemory.fact)'")
            } else if !isDuplicateMemory(newMemory, in: existingMemories) {
                uniqueMemories.append(newMemory)
                print(">>> [MEMORY] Stored: \(newMemory.fact)")
            }
        }
        
        return (uniqueMemories, memoriesToUpdate)
    }
    
    // MARK: - Memory Retrieval
    
    /// Find memories relevant to the current message
    private func findRelevantMemories(for message: String, in memories: [Memory], limit: Int) -> [Memory] {
        guard !memories.isEmpty else {
            print(">>> [MEMORY] No memories to search")
            return []
        }
        
        print(">>> [MEMORY] Searching \(memories.count) memories for: '\(message)'")
        
        let messageLower = message.lowercased()
        let messageWords = Set(messageLower.components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 2 })
        
        print(">>> [MEMORY] Search keywords: \(messageWords)")
        
        // Score each memory based on relevance
        var scoredMemories: [(memory: Memory, score: Double)] = []
        
        for memory in memories {
            var score: Double = 0
            
            // Check if any tags match words in the message (HIGH PRIORITY)
            for tag in memory.tags {
                if messageWords.contains(tag) {
                    score += 10.0
                    print(">>> [MEMORY] Tag exact match '\(tag)': +10")
                } else if messageLower.contains(tag) {
                    score += 5.0
                    print(">>> [MEMORY] Tag partial match '\(tag)': +5")
                }
            }
            
            // Check if the fact itself contains relevant keywords
            let factLower = memory.fact.lowercased()
            for word in messageWords {
                if factLower.contains(word) {
                    score += 3.0
                    print(">>> [MEMORY] Fact contains '\(word)': +3")
                }
            }
            
            // Boost by importance
            let importanceBoost = Double(memory.importance)
            score *= importanceBoost
            
            // Slight boost for recent memories
            let daysSinceCreated = Date().timeIntervalSince(memory.timestamp) / 86400
            if daysSinceCreated < 7 {
                score *= 1.2
            }
            
            print(">>> [MEMORY] Memory '\(memory.fact)' scored: \(score)")
            
            if score > 0 {
                scoredMemories.append((memory, score))
            }
        }
        
        // Sort by score and return top N
        let topMemories = scoredMemories
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.memory }
        
        print(">>> [MEMORY] Returning \(topMemories.count) relevant memories")
        for memory in topMemories {
            print(">>> [MEMORY] - \(memory.fact)")
        }
        
        return topMemories
    }
    
    // MARK: - Helper Methods
    
    /// Check if a memory is a duplicate
    private func isDuplicateMemory(_ newMemory: Memory, in existingMemories: [Memory]) -> Bool {
        for existing in existingMemories {
            // Check for exact match
            if existing.fact.lowercased() == newMemory.fact.lowercased() {
                return true
            }
            
            // Check for very similar facts (>80% word overlap)
            let existingWords = Set(existing.fact.lowercased().components(separatedBy: .whitespacesAndNewlines))
            let newWords = Set(newMemory.fact.lowercased().components(separatedBy: .whitespacesAndNewlines))
            
            let intersection = existingWords.intersection(newWords)
            let union = existingWords.union(newWords)
            
            let similarity = Double(intersection.count) / Double(union.count)
            if similarity > 0.8 {
                return true
            }
        }
        
        return false
    }
    
    /// Find a conflicting memory that should be updated
    private func findConflictingMemory(_ newMemory: Memory, in existingMemories: [Memory]) -> Memory? {
        // Check if new memory conflicts with existing ones based on category
        for existing in existingMemories {
            // If same category
            if existing.category == newMemory.category {
                // Check if facts are actually different
                let existingWords = Set(existing.fact.lowercased().components(separatedBy: .whitespacesAndNewlines))
                let newWords = Set(newMemory.fact.lowercased().components(separatedBy: .whitespacesAndNewlines))
                
                let intersection = existingWords.intersection(newWords)
                let union = existingWords.union(newWords)
                let similarity = Double(intersection.count) / Double(union.count)
                
                // If similar category but different facts, might be conflict
                if similarity > 0.3 && similarity < 0.6 {
                    return existing
                }
            }
        }
        
        return nil
    }
    
    /// Check if a memory matches something the user deleted (blacklisted)
    private func isBlacklisted(_ newMemory: Memory, in blacklistedMemories: [Memory]) -> Bool {
        for blacklisted in blacklistedMemories {
            // Check for exact match
            if blacklisted.fact.lowercased() == newMemory.fact.lowercased() {
                return true
            }
            
            // Check for high similarity (>70% word overlap)
            let blacklistedWords = Set(blacklisted.fact.lowercased().components(separatedBy: .whitespacesAndNewlines))
            let newWords = Set(newMemory.fact.lowercased().components(separatedBy: .whitespacesAndNewlines))
            
            let intersection = blacklistedWords.intersection(newWords)
            let union = blacklistedWords.union(newWords)
            
            let similarity = Double(intersection.count) / Double(union.count)
            if similarity > 0.7 {
                return true
            }
        }
        
        return false
    }
    
    /// Call Gemini for memory extraction (non-streaming)
    private func callGeminiForExtraction(prompt: String) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent?key=\(Config.geminiAPIKey)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.3,
                "maxOutputTokens": 1000
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MemoryError.extractionFailed
        }
        
        // Parse Gemini response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw MemoryError.invalidResponse
        }
        
        // Clean up the response
        var cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedText.hasPrefix("```json") {
            cleanedText = cleanedText.replacingOccurrences(of: "```json", with: "")
            cleanedText = cleanedText.replacingOccurrences(of: "```", with: "")
            cleanedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return cleanedText
    }
}

// MARK: - Response Models

struct MemoryExtractionResponse: Codable {
    let memories: [ExtractedMemory]
}

struct ExtractedMemory: Codable {
    let fact: String
    let category: String
    let tags: [String]
    let importance: Int
    let psychologicalInsight: ExtractedPsychologicalInsight?
    
    enum CodingKeys: String, CodingKey {
        case fact
        case category
        case tags
        case importance
        case psychologicalInsight = "psychological_insight"
    }
}

struct ExtractedPsychologicalInsight: Codable {
    let patternType: String?
    let cognitiveDistortion: String?
    let effectiveTechnique: String?
    let triggerIdentified: String?
    
    enum CodingKeys: String, CodingKey {
        case patternType = "pattern_type"
        case cognitiveDistortion = "cognitive_distortion"
        case effectiveTechnique = "effective_technique"
        case triggerIdentified = "trigger_identified"
    }
}

enum MemoryError: Error {
    case extractionFailed
    case invalidResponse
}
