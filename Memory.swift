import Foundation

struct Memory: Identifiable, Codable, Equatable {
    let id: UUID
    let fact: String
    let source: MemorySource
    let timestamp: Date
    let category: MemoryCategory
    let importance: Int // 1-10
    
    // Tags for search
    var tags: [String]
    
    // Psychological fields
    var psychologicalInsight: PsychologicalInsight?
    var relatedEmotions: [String] // Just strings now
    var triggerContext: String?
    
    init(id: UUID = UUID(),
         fact: String,
         source: MemorySource = .conversation,
         timestamp: Date = Date(),
         category: MemoryCategory = .general,
         importance: Int = 5,
         tags: [String] = [],
         psychologicalInsight: PsychologicalInsight? = nil,
         relatedEmotions: [String] = [],
         triggerContext: String? = nil) {
        self.id = id
        self.fact = fact
        self.source = source
        self.timestamp = timestamp
        self.category = category
        self.importance = importance
        self.tags = tags
        self.psychologicalInsight = psychologicalInsight
        self.relatedEmotions = relatedEmotions
        self.triggerContext = triggerContext
    }
    
    static func == (lhs: Memory, rhs: Memory) -> Bool {
        return lhs.id == rhs.id
    }
}

enum MemorySource: String, Codable {
    case conversation
    case userProvided
    case inferred
    case psychologicalAssessment
}

enum MemoryCategory: String, Codable {
    case general
    case preferences
    case relationships
    case work
    case health
    case goals
    case triggers
    case copingStrategies
    case psychologicalPattern
}

// Psychological insight attached to memories
struct PsychologicalInsight: Codable {
    let patternType: PatternType?
    let cognitiveDistortion: CognitiveDistortion?
    let effectiveTechnique: String?
    let triggerIdentified: String?
    
    init(patternType: PatternType? = nil,
         cognitiveDistortion: CognitiveDistortion? = nil,
         effectiveTechnique: String? = nil,
         triggerIdentified: String? = nil) {
        self.patternType = patternType
        self.cognitiveDistortion = cognitiveDistortion
        self.effectiveTechnique = effectiveTechnique
        self.triggerIdentified = triggerIdentified
    }
}

// MARK: - Psychological Pattern Types (kept from deleted file)

enum PatternType: String, Codable {
    case recurringAnxiety
    case depressiveEpisodes
    case angerOutbursts
    case avoidanceBehavior
    case catastrophizingPattern
    case perfectionism
    case socialWithdrawal
    case sleepDisturbance
    case substanceUse
    case selfCriticism
    case relationshipConflict
    case workStress
    case academicPressure
}

// MARK: - Cognitive Distortions (kept from deleted file)

enum CognitiveDistortion: String, Codable, CaseIterable {
    case catastrophizing
    case blackAndWhiteThinking
    case overgeneralization
    case mindReading
    case fortuneTelling
    case emotionalReasoning
    case shouldStatements
    case labeling
    case personalization
    case mentalFilter
    case discountingPositives
    
    var explanation: String {
        switch self {
        case .catastrophizing:
            return "Assuming the worst possible outcome"
        case .blackAndWhiteThinking:
            return "Seeing things in extremes with no middle ground"
        case .overgeneralization:
            return "Drawing broad conclusions from single events"
        case .mindReading:
            return "Assuming you know what others think"
        case .fortuneTelling:
            return "Predicting negative outcomes without evidence"
        case .emotionalReasoning:
            return "Believing feelings reflect reality"
        case .shouldStatements:
            return "Rigid rules about how things 'should' be"
        case .labeling:
            return "Defining yourself or others by single traits"
        case .personalization:
            return "Taking responsibility for things outside your control"
        case .mentalFilter:
            return "Focusing only on negatives while ignoring positives"
        case .discountingPositives:
            return "Dismissing positive experiences as 'not counting'"
        }
    }
}
