import Foundation
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var currentCompanion: Companion
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let geminiLiveService: GeminiLiveService
    private let elevenLabsService: ElevenLabsService
    let storageService: StorageService // Made public for MemoriesView
    private let memoryService: MemoryService
    private var currentConversation: Conversation
    private var isServiceConnected = false
    
    init(companion: Companion = .theo) {
        self.currentCompanion = companion
        self.storageService = StorageService()
        self.geminiLiveService = GeminiLiveService(apiKey: Config.geminiAPIKey)
        self.elevenLabsService = ElevenLabsService(apiKey: Config.elevenLabsAPIKey)
        self.memoryService = MemoryService(geminiService: geminiLiveService, storageService: storageService)
        
        // Load or create conversation
        let savedConversations = storageService.loadConversations()
        if let existing = savedConversations.first(where: { $0.companion == companion }) {
            self.currentConversation = existing
            self.messages = existing.messages
        } else {
            self.currentConversation = Conversation(companion: companion)
        }
        
        // Connect to Gemini Live
        Task {
            await connectToGemini()
        }
    }
    
    private func connectToGemini() async {
        do {
            try await geminiLiveService.connect(companion: currentCompanion)
            isServiceConnected = true
            print(">>> [INFO] Connected to Gemini Live")
        } catch {
            print(">>> [ERROR] Failed to connect to Gemini Live: \(error)")
            errorMessage = "Failed to connect to Gemini"
        }
    }
    
    func sendMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        // Ensure we're connected
        if !isServiceConnected {
            await connectToGemini()
        }
        
        isLoading = true
        errorMessage = nil
        
        // Add user message
        let userMessage = Message(content: text, isUser: true, companion: currentCompanion)
        messages.append(userMessage)
        currentConversation.addMessage(userMessage)
        
        // Build memory context
        let memoryContext = memoryService.buildContext(
            for: currentConversation,
            currentMessage: text
        )
        
        // Prepare message with context
        var messageToSend = text
        if !memoryContext.isEmpty {
            messageToSend = memoryContext + "\nUser's message: " + text
        }
        
        // Prepare for response
        let companionMessageID = UUID()
        var fullResponse = ""
        
        // Get voice ID
        let voiceID = currentCompanion == .theo ? Config.theoVoiceID : Config.mavenVoiceID
        
        // Start ElevenLabs stream
        do {
            try await elevenLabsService.startStream(voiceID: voiceID)
        } catch {
            print(">>> [ERROR] Failed to start ElevenLabs stream: \(error)")
        }
        
        // Set up callbacks
        geminiLiveService.onTextChunk = { [weak self] chunk in
            guard let self = self else { return }
            
            Task { @MainActor in
                fullResponse += chunk
                
                // Update or add the message
                if let index = self.messages.firstIndex(where: { $0.id == companionMessageID }) {
                    self.messages[index] = Message(id: companionMessageID,
                                                  content: fullResponse,
                                                  isUser: false,
                                                  companion: self.currentCompanion)
                } else {
                    let msg = Message(id: companionMessageID,
                                    content: fullResponse,
                                    isUser: false,
                                    companion: self.currentCompanion)
                    self.messages.append(msg)
                }
                
                // Send chunk to ElevenLabs
                Task {
                    do {
                        try await self.elevenLabsService.sendTextChunk(chunk)
                    } catch {
                        print(">>> [ERROR] Failed to send chunk to ElevenLabs: \(error)")
                    }
                }
            }
        }
        
        geminiLiveService.onComplete = { [weak self] in
            guard let self = self else { return }
            
            Task { @MainActor in
                // Save final message
                let finalMessage = Message(id: companionMessageID,
                                         content: fullResponse,
                                         isUser: false,
                                         companion: self.currentCompanion)
                self.currentConversation.addMessage(finalMessage)
                self.saveConversation()
                
                // End ElevenLabs stream
                do {
                    try await self.elevenLabsService.endStream()
                } catch {
                    print(">>> [ERROR] Failed to end ElevenLabs stream: \(error)")
                }
                
                // Extract memories from recent conversation
                let recentMessages = self.currentConversation.getRecentMessages(count: 6)
                if recentMessages.count >= 4 {
                    do {
                        let (newMemories, updatedMemories) = try await self.memoryService.extractAndStoreMemories(
                            from: self.currentConversation,
                            recentMessages: recentMessages
                        )
                        
                        // Load current memories
                        var allMemories = self.storageService.loadGlobalMemories()
                        
                        // Handle updates: replace old memories with new ones
                        for (oldMemory, newMemory) in updatedMemories {
                            if let index = allMemories.firstIndex(where: { $0.id == oldMemory.id }) {
                                allMemories[index] = newMemory
                            }
                        }
                        
                        // Add new memories
                        allMemories.append(contentsOf: newMemories)
                        
                        // Save updated memory bank
                        self.storageService.saveGlobalMemories(allMemories)
                    } catch {
                        print(">>> [ERROR] Failed to extract memories: \(error)")
                    }
                }
                
                // Summarize if needed
                
                
                self.isLoading = false
            }
        }
        
        // Send message to Gemini (with memory context injected)
        do {
            try await geminiLiveService.sendMessage(messageToSend)
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
            print("Error: \(error)")
            isLoading = false
        }
    }
    
    func clearChatView() {
        // Clear only the visible messages, keep the stored conversation
        messages = []
    }
    
    func reconnectGemini() async {
        // Disconnect and reconnect to clear Gemini's context
        geminiLiveService.disconnect()
        isServiceConnected = false
        await connectToGemini()
        print(">>> [INFO] Reconnected to Gemini after memory change")
    }
    
    func switchCompanion(to newCompanion: Companion) {
        // Disconnect current session
        geminiLiveService.disconnect()
        isServiceConnected = false
        
        // Save current conversation
        saveConversation()
        
        // Load or create new conversation
        let savedConversations = storageService.loadConversations()
        if let existing = savedConversations.first(where: { $0.companion == newCompanion }) {
            currentConversation = existing
            messages = existing.messages
        } else {
            currentConversation = Conversation(companion: newCompanion)
            messages = []
        }
        
        currentCompanion = newCompanion
        storageService.saveSelectedCompanion(newCompanion)
        
        // Reconnect with new companion
        Task {
            await connectToGemini()
        }
    }
    
    private func saveConversation() {
        var allConversations = storageService.loadConversations()
        
        // Remove old version of this conversation
        allConversations.removeAll { $0.companion == currentCompanion }
        
        // Add updated conversation
        allConversations.append(currentConversation)
        
        // Save
        storageService.saveConversations(allConversations)
    }
}
