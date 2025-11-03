import Foundation

class SubscriptionService {
    private let storageService: StorageService
    
    init(storageService: StorageService) {
        self.storageService = storageService
    }
    
    /// Get current subscription tier (FAKE VERSION - for testing)
    func getCurrentTier() -> SubscriptionTier {
        // Check if we have a saved tier (for manual testing)
        if let savedTier = storageService.loadSubscriptionTier() {
            return savedTier
        }
        
        // Otherwise, check trial status
        let trialInfo = getTrialInfo()
        
        if trialInfo.isActive {
            return .trial
        } else {
            return .expired
        }
    }
    
    /// Get trial information
    func getTrialInfo() -> (isActive: Bool, daysRemaining: Int) {
        let trialStartDate = storageService.loadTrialStartDate() ?? Date()
        
        // If no trial start date, start trial now
        if storageService.loadTrialStartDate() == nil {
            storageService.saveTrialStartDate(trialStartDate)
        }
        
        let calendar = Calendar.current
        let daysSinceStart = calendar.dateComponents([.day], from: trialStartDate, to: Date()).day ?? 0
        
        let daysRemaining = max(0, 7 - daysSinceStart)
        let isActive = daysRemaining > 0
        
        return (isActive, daysRemaining)
    }
    
    /// Manually set tier (for testing only - remove when StoreKit is implemented)
    func setTierForTesting(_ tier: SubscriptionTier) {
        print(">>> [SUBSCRIPTION] ⚠️ Manually setting tier to: \(tier.rawValue)")
        storageService.saveSubscriptionTier(tier)
    }
    
    /// Check if user needs to upgrade
    func shouldShowUpgradePrompt() -> Bool {
        let tier = getCurrentTier()
        return tier == .expired
    }
    
    /// Get upgrade message based on current tier
    func getUpgradeMessage() -> String {
        let tier = getCurrentTier()
        
        switch tier {
        case .trial:
            let trialInfo = getTrialInfo()
            return "Trial: \(trialInfo.daysRemaining) days remaining"
        case .tier1:
            return "Upgrade to Tier 2 for 90 min/day + rollover"
        case .tier2:
            return "Premium Member"
        case .expired:
            return "Trial expired - Upgrade to continue using voice"
        }
    }
}

// MARK: - TODO: Real StoreKit Implementation
// When ready to implement real subscriptions:
// 1. Add StoreKit 2 framework
// 2. Create product IDs in App Store Connect
// 3. Replace getCurrentTier() with receipt validation
// 4. Add purchase flow
// 5. Handle subscription renewals/expirations
// 6. Remove setTierForTesting() method
