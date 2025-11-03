import Foundation

class StorageService {
    private let conversationsKey = "saved_conversations"
    private let selectedCompanionKey = "selected_companion"
    private let globalMemoriesKey = "global_memories"
    private let blacklistedMemoriesKey = "blacklisted_memories"
    private let voiceQuotaKey = "voice_quota"
    private let subscriptionTierKey = "subscription_tier"
    private let trialStartDateKey = "trial_start_date"
    
    // MARK: - Conversations
    
    func saveConversations(_ conversations: [Conversation]) {
        if let encoded = try? JSONEncoder().encode(conversations) {
            UserDefaults.standard.set(encoded, forKey: conversationsKey)
        }
    }
    
    func loadConversations() -> [Conversation] {
        guard let data = UserDefaults.standard.data(forKey: conversationsKey),
              let conversations = try? JSONDecoder().decode([Conversation].self, from: data) else {
            return []
        }
        return conversations
    }
    
    // MARK: - Selected Companion
    
    func saveSelectedCompanion(_ companion: Companion) {
        UserDefaults.standard.set(companion.rawValue, forKey: selectedCompanionKey)
    }
    
    func loadSelectedCompanion() -> Companion? {
        guard let companionString = UserDefaults.standard.string(forKey: selectedCompanionKey),
              let companion = Companion(rawValue: companionString) else {
            return nil
        }
        return companion
    }
    
    // MARK: - Global Memories
    
    func saveGlobalMemories(_ memories: [Memory]) {
        if let encoded = try? JSONEncoder().encode(memories) {
            UserDefaults.standard.set(encoded, forKey: globalMemoriesKey)
        }
    }
    
    func loadGlobalMemories() -> [Memory] {
        guard let data = UserDefaults.standard.data(forKey: globalMemoriesKey),
              let memories = try? JSONDecoder().decode([Memory].self, from: data) else {
            return []
        }
        return memories
    }
    
    // MARK: - Blacklisted Memories
    
    func saveBlacklistedMemories(_ memories: [Memory]) {
        if let encoded = try? JSONEncoder().encode(memories) {
            UserDefaults.standard.set(encoded, forKey: blacklistedMemoriesKey)
        }
    }
    
    func loadBlacklistedMemories() -> [Memory] {
        guard let data = UserDefaults.standard.data(forKey: blacklistedMemoriesKey),
              let memories = try? JSONDecoder().decode([Memory].self, from: data) else {
            return []
        }
        return memories
    }
    
    // MARK: - Voice Quota
    
    func saveVoiceQuota(_ quota: VoiceQuota) {
        if let encoded = try? JSONEncoder().encode(quota) {
            UserDefaults.standard.set(encoded, forKey: voiceQuotaKey)
        }
    }
    
    func loadVoiceQuota() -> VoiceQuota {
        guard let data = UserDefaults.standard.data(forKey: voiceQuotaKey),
              let quota = try? JSONDecoder().decode(VoiceQuota.self, from: data) else {
            return VoiceQuota(tier: .trial)
        }
        return quota
    }
    
    // MARK: - Subscription Tier
    
    func saveSubscriptionTier(_ tier: SubscriptionTier) {
        UserDefaults.standard.set(tier.rawValue, forKey: subscriptionTierKey)
    }
    
    func loadSubscriptionTier() -> SubscriptionTier? {
        guard let tierString = UserDefaults.standard.string(forKey: subscriptionTierKey),
              let tier = SubscriptionTier(rawValue: tierString) else {
            return nil
        }
        return tier
    }
    
    // MARK: - Trial Start Date
    
    func saveTrialStartDate(_ date: Date) {
        UserDefaults.standard.set(date, forKey: trialStartDateKey)
    }
    
    func loadTrialStartDate() -> Date? {
        return UserDefaults.standard.object(forKey: trialStartDateKey) as? Date
    }
    
    // MARK: - Clear All Data
    
    func clearAllData() {
        UserDefaults.standard.removeObject(forKey: conversationsKey)
        UserDefaults.standard.removeObject(forKey: selectedCompanionKey)
        UserDefaults.standard.removeObject(forKey: globalMemoriesKey)
        UserDefaults.standard.removeObject(forKey: blacklistedMemoriesKey)
        UserDefaults.standard.removeObject(forKey: voiceQuotaKey)
        UserDefaults.standard.removeObject(forKey: subscriptionTierKey)
        UserDefaults.standard.removeObject(forKey: trialStartDateKey)
        print(">>> [STORAGE] Nuclear reset - all data cleared")
    }
}
