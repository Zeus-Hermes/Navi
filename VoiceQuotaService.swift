import Foundation

class VoiceQuotaService {
    private let storageService: StorageService
    private var currentQuota: VoiceQuota
    
    init(storageService: StorageService) {
        self.storageService = storageService
        self.currentQuota = storageService.loadVoiceQuota()
        
        // Check if we need to reset for a new day
        checkAndResetIfNeeded()
    }
    
    /// Check if it's a new day and reset quota if needed
    private func checkAndResetIfNeeded() {
        if currentQuota.needsReset() {
            resetDailyQuota()
        }
    }
    
    /// Reset quota for a new day
    private func resetDailyQuota() {
        print(">>> [QUOTA] Resetting daily quota - new day!")
        
        // Calculate rollover for Tier 2
        var rollover = 0
        if currentQuota.tier.supportsRollover {
            let unused = currentQuota.remainingSeconds
            rollover = min(unused, currentQuota.tier.maxRollover - currentQuota.tier.dailyVoiceLimit)
            rollover = max(0, rollover) // Don't allow negative rollover
            print(">>> [QUOTA] Tier 2 rollover: \(rollover) seconds")
        }
        
        // Reset
        currentQuota.secondsUsedToday = 0
        currentQuota.lastResetDate = Date()
        currentQuota.rolloverSeconds = rollover
        
        saveQuota()
        
        print(">>> [QUOTA] New quota - Daily limit: \(currentQuota.tier.dailyVoiceLimit)s, Rollover: \(rollover)s, Total: \(currentQuota.remainingSeconds)s")
    }
    
    /// Check if user can use voice
    func canUseVoice() -> Bool {
        checkAndResetIfNeeded()
        let can = currentQuota.canUseVoice
        print(">>> [QUOTA] Can use voice: \(can) (Remaining: \(currentQuota.formattedRemainingTime))")
        return can
    }
    
    /// Get remaining seconds
    func getRemainingSeconds() -> Int {
        checkAndResetIfNeeded()
        return currentQuota.remainingSeconds
    }
    
    /// Get formatted remaining time (e.g., "27:35")
    func getFormattedRemainingTime() -> String {
        checkAndResetIfNeeded()
        return currentQuota.formattedRemainingTime
    }
    
    /// Deduct usage after audio plays
    func deductUsage(seconds: Int) {
        print(">>> [QUOTA] Deducting \(seconds) seconds from quota")
        
        currentQuota.secondsUsedToday += seconds
        saveQuota()
        
        let remaining = currentQuota.remainingSeconds
        print(">>> [QUOTA] Remaining after deduction: \(remaining)s (\(currentQuota.formattedRemainingTime))")
        
        if remaining <= 0 {
            print(">>> [QUOTA] ⚠️ Voice quota exhausted!")
        }
    }
    
    /// Update subscription tier (when user upgrades/downgrades)
    func updateTier(_ newTier: SubscriptionTier) {
        print(">>> [QUOTA] Updating tier: \(currentQuota.tier.rawValue) → \(newTier.rawValue)")
        
        currentQuota.tier = newTier
        
        // If upgrading to Tier 2 mid-day, don't reset - just update the tier
        // They'll get the full benefits on next reset
        
        saveQuota()
    }
    
    /// Get current tier
    func getCurrentTier() -> SubscriptionTier {
        return currentQuota.tier
    }
    
    private func saveQuota() {
        storageService.saveVoiceQuota(currentQuota)
    }
}
