import Foundation
import Combine
import AVFoundation

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var currentCompanion: Companion
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var voiceQuotaRemaining: String = "30:00"
    @Published var showUpgradePrompt = false
    
    // Voice recording
    @Published var isRecordingVoice = false
    @Published var recordingDuration: TimeInterval = 0
    
    private let geminiLiveService: GeminiLiveService
    private let openAITTSService: OpenAITTSService
    let storageService: StorageService
    private let memoryService: MemoryService
    private let voiceQuotaService: VoiceQuotaService
    private let subscriptionService: SubscriptionService
    private var currentConversation: Conversation
    private var isServiceConnected = false
    
    // Voice services
    private let audioStreamingService = AudioStreamingService()
    private let whisperService = LocalWhisperService()
    private var recordingTimer: Timer?
    private var isWhisperReady = false
    
    init(companion: Companion = .theo) {
        self.currentCompanion = companion
        self.storageService = StorageService()
        self.geminiLiveService = GeminiLiveService(apiKey: Config.geminiAPIKey)
        self.openAITTSService = OpenAITTSService(apiKey: Config.openAIAPIKey)
        self.memoryService = MemoryService(geminiService: geminiLiveService, storageService: storageService)
        self.subscriptionService = SubscriptionService(storageService: storageService)
        self.voiceQuotaService = VoiceQuotaService(storageService: storageService)
        
        self.voiceQuotaRemaining = voiceQuotaService.getFormattedRemainingTime()
        
        let savedConversations = storageService.loadConversations()
        if let existing = savedConversations.first(where: { $0.companion == companion }) {
            self.currentConversation = existing
            self.messages = existing.messages
        } else {
            self.currentConversation = Conversation(companion: companion)
        }
        
        Task {
            await connectToGemini()
        }
        
        Task {
            await initializeWhisper()
        }
    }
    
    private func initializeWhisper() async {
        do {
            try await whisperService.initialize()
            isWhisperReady = true
            print(">>> [CHAT] Whisper ready")
        } catch {
            print(">>> [CHAT] Whisper init failed: \(error)")
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
        
        if !isServiceConnected {
            await connectToGemini()
        }
        
        isLoading = true
        errorMessage = nil
        
        let hasVoiceQuota = voiceQuotaService.canUseVoice()
        
        let userMessage = Message(content: text, isUser: true, companion: currentCompanion)
        messages.append(userMessage)
        currentConversation.addMessage(userMessage)
        
        let memoryContext = memoryService.buildContext(
            for: currentConversation,
            currentMessage: text
        )
        
        var messageToSend = text
        if !memoryContext.isEmpty {
            messageToSend = memoryContext + "\nUser's message: " + text
        }
        
        let companionMessageID = UUID()
        var fullResponse = ""
        
        geminiLiveService.onTextChunk = { [weak self] chunk in
            guard let self = self else { return }
            
            Task { @MainActor in
                fullResponse += chunk
                
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
            }
        }
        
        geminiLiveService.onComplete = { [weak self] in
            guard let self = self else { return }
            
            Task { @MainActor in
                let finalMessage = Message(id: companionMessageID,
                                         content: fullResponse,
                                         isUser: false,
                                         companion: self.currentCompanion)
                self.currentConversation.addMessage(finalMessage)
                self.saveConversation()
                
                if hasVoiceQuota {
                    do {
                        print(">>> [CHAT] Generating audio for response...")
                        let audioDuration = try await self.openAITTSService.generateAndPlaySpeech(
                            text: fullResponse,
                            companion: self.currentCompanion
                        )
                        
                        self.voiceQuotaService.deductUsage(seconds: audioDuration)
                        self.voiceQuotaRemaining = self.voiceQuotaService.getFormattedRemainingTime()
                        
                        if !self.voiceQuotaService.canUseVoice() {
                            self.showUpgradePrompt = true
                        }
                    } catch {
                        print(">>> [ERROR] Failed to generate audio: \(error)")
                        self.errorMessage = "Voice generation failed. Continuing with text only."
                    }
                } else {
                    print(">>> [CHAT] No voice quota remaining - text only mode")
                    self.showUpgradePrompt = true
                }
                
                let recentMessages = self.currentConversation.getRecentMessages(count: 6)
                if recentMessages.count >= 4 {
                    do {
                        let (newMemories, updatedMemories) = try await self.memoryService.extractAndStoreMemories(
                            from: self.currentConversation,
                            recentMessages: recentMessages
                        )
                        
                        var allMemories = self.storageService.loadGlobalMemories()
                        
                        for (oldMemory, newMemory) in updatedMemories {
                            if let index = allMemories.firstIndex(where: { $0.id == oldMemory.id }) {
                                allMemories[index] = newMemory
                            }
                        }
                        
                        allMemories.append(contentsOf: newMemories)
                        self.storageService.saveGlobalMemories(allMemories)
                    } catch {
                        print(">>> [ERROR] Failed to extract memories: \(error)")
                    }
                }
                
                self.isLoading = false
            }
        }
        
        do {
            try await geminiLiveService.sendMessage(messageToSend)
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
            print("Error: \(error)")
            isLoading = false
        }
    }
    
    // MARK: - Voice Recording
    
    func startVoiceRecording() {
        guard !isRecordingVoice, isWhisperReady else { return }
        
        do {
            try audioStreamingService.startRecording()
            isRecordingVoice = true
            recordingDuration = 0
            
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.recordingDuration += 0.1
                }
            }
            
            print(">>> [CHAT] 🎤 Recording started")
        } catch {
            errorMessage = "Failed to start recording"
            print(">>> [CHAT] ❌ Recording failed: \(error)")
        }
    }
    
    func stopVoiceRecording() async {
        guard isRecordingVoice else { return }
        
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        let audioData = audioStreamingService.stopRecording()
        isRecordingVoice = false
        
        print(">>> [CHAT] 🎤 Recording stopped, transcribing...")
        
        // Save to temp file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice_\(UUID().uuidString).wav")
        
        guard writeWAVFile(audioData: audioData, to: tempURL) else {
            errorMessage = "Failed to process audio"
            return
        }
        
        do {
            let transcript = try await whisperService.transcribe(audioPath: tempURL.path)
            print(">>> [CHAT] ✅ Transcript: \(transcript)")
            
            try? FileManager.default.removeItem(at: tempURL)
            
            // Send to Gemini
            await sendMessage(transcript)
            
        } catch {
            print(">>> [CHAT] ❌ Transcription failed: \(error)")
            errorMessage = "Transcription failed"
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
    
    private func writeWAVFile(audioData: Data, to url: URL) -> Bool {
        let sampleRate: UInt32 = 16000
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample: UInt16 = bitsPerSample / 8
        let blockAlign: UInt16 = numChannels * bytesPerSample
        let byteRate: UInt32 = sampleRate * UInt32(blockAlign)
        let dataSize = UInt32(audioData.count)
        let fileSize = dataSize + 36
        
        var header = Data()
        header.append("RIFF".data(using: .ascii)!)
        header.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        header.append("data".data(using: .ascii)!)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        
        do {
            try (header + audioData).write(to: url)
            return true
        } catch {
            return false
        }
    }
    
    func clearChatView() {
        messages = []
    }
    
    func reconnectGemini() async {
        geminiLiveService.disconnect()
        isServiceConnected = false
        await connectToGemini()
        print(">>> [INFO] Reconnected to Gemini after memory change")
    }
    
    func switchCompanion(to newCompanion: Companion) {
        geminiLiveService.disconnect()
        isServiceConnected = false
        saveConversation()
        
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
        voiceQuotaRemaining = voiceQuotaService.getFormattedRemainingTime()
        
        Task {
            await connectToGemini()
        }
    }
    
    private func saveConversation() {
        var allConversations = storageService.loadConversations()
        allConversations.removeAll { $0.companion == currentCompanion }
        allConversations.append(currentConversation)
        storageService.saveConversations(allConversations)
    }
}
