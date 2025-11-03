import Foundation

enum SubscriptionTier: String, Codable {
    case trial = "Trial"
    case tier1 = "Tier 1"
    case tier2 = "Tier 2"
    case expired = "Expired"
    
    /// Daily voice limit in seconds
    var dailyVoiceLimit: Int {
        switch self {
        case .trial:
            return 1800 // 30 minutes
        case .tier1:
            return 1800 // 30 minutes
        case .tier2:
            return 5400 // 90 minutes
        case .expired:
            return 0 // No voice access
        }
    }
    
    /// Whether this tier supports rollover minutes
    var supportsRollover: Bool {
        switch self {
        case .tier2:
            return true
        default:
            return false
        }
    }
    
    /// Maximum rollover seconds (only for Tier 2)
    var maxRollover: Int {
        return 5400 // 90 minutes total including rollover
    }
}
