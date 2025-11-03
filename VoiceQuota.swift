import Foundation

struct VoiceQuota: Codable {
    var tier: SubscriptionTier
    var secondsUsedToday: Int
    var lastResetDate: Date
    var rolloverSeconds: Int // Only used for Tier 2
    
    init(tier: SubscriptionTier = .trial) {
        self.tier = tier
        self.secondsUsedToday = 0
        self.lastResetDate = Date()
        self.rolloverSeconds = 0
    }
    
    /// Remaining seconds of voice time today
    var remainingSeconds: Int {
        let dailyLimit = tier.dailyVoiceLimit
        let rollover = tier.supportsRollover ? rolloverSeconds : 0
        let totalAvailable = dailyLimit + rollover
        let remaining = totalAvailable - secondsUsedToday
        return remaining
    }
    
    /// Whether user can use voice (even if just 1 second remaining)
    var canUseVoice: Bool {
        return remainingSeconds > 0
    }
    
    /// Formatted remaining time (e.g., "27:35")
    var formattedRemainingTime: String {
        let totalSeconds = max(0, remainingSeconds) // Don't show negative
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Check if we need to reset (new day)
    func needsReset() -> Bool {
        let calendar = Calendar.current
        let lastReset = calendar.startOfDay(for: lastResetDate)
        let today = calendar.startOfDay(for: Date())
        return today > lastReset
    }
}
