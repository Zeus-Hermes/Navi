import Foundation
import AVFoundation

class OpenAITTSService {
    private let apiKey: String
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioStartTime: Date?
    
    init(apiKey: String) {
        self.apiKey = apiKey
        // DON'T setup audio engine here - do it on demand
    }
    
    private func setupAudioEngine() {
        // Clean up any existing engine first
        cleanupAudioEngine()
        
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        
        guard let engine = audioEngine, let player = playerNode else {
            print(">>> [TTS ERROR] Failed to create engine/player")
            return
        }
        
        engine.attach(player)
        
        // PCM format: 24kHz, 16-bit, mono (matches OpenAI TTS output)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                  sampleRate: 24000,
                                  channels: 1,
                                  interleaved: true)
        
        if let format = format {
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        
        print(">>> [TTS] Audio engine created (not started yet)")
    }
    
    private func cleanupAudioEngine() {
        playerNode?.stop()
        audioEngine?.stop()
        
        if let player = playerNode, let engine = audioEngine {
            engine.detach(player)
        }
        
        playerNode = nil
        audioEngine = nil
        
        print(">>> [TTS] Audio engine cleaned up")
    }
    
    /// Generate speech from text and play it
    /// Returns the duration in seconds after audio finishes
    func generateAndPlaySpeech(text: String, companion: Companion) async throws -> Int {
        print(">>> [TTS] Generating speech for: \(text.prefix(50))...")
        
        // Create fresh audio engine
        setupAudioEngine()
        
        // Configure audio session for playback
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            print(">>> [TTS DEBUG] BEFORE - Category: \(audioSession.category), Mode: \(audioSession.mode)")
            print(">>> [TTS DEBUG] BEFORE - Active: \(audioSession.isOtherAudioPlaying)")
            
            // Force a clean slate
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            
            // Small delay to let iOS clean up
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Now configure for playback
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [])
            try audioSession.setActive(true, options: [])
            
            print(">>> [TTS DEBUG] AFTER - Category: \(audioSession.category), Mode: \(audioSession.mode)")
            print(">>> [TTS DEBUG] AFTER - Route: \(audioSession.currentRoute)")
            
            print(">>> [TTS] Audio session configured for playback")
        } catch {
            print(">>> [TTS] ⚠️ Audio session setup failed: \(error)")
            cleanupAudioEngine()
            throw error
        }
        
        // Start the audio engine
        guard let audioEngine = audioEngine, let playerNode = playerNode else {
            throw TTSError.audioSetupFailed
        }
        
        do {
            try audioEngine.start()
            playerNode.play()
            print(">>> [TTS] Audio engine started")
        } catch {
            print(">>> [TTS] ⚠️ Failed to start audio engine: \(error)")
            cleanupAudioEngine()
            throw error
        }
        
        print(">>> [TTS DEBUG] Player node playing: \(playerNode.isPlaying)")
        print(">>> [TTS DEBUG] Audio engine running: \(audioEngine.isRunning)")
        
        // Determine voice based on companion
        let voice = companion == .theo ? "fable" : "shimmer"
        
        // Get personality instructions from companion
        let instructions = companion.systemPrompt
        
        // Make API request
        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini-tts",
            "voice": voice,
            "input": text,
            "instructions": instructions,
            "response_format": "pcm"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        print(">>> [TTS] Sending request to OpenAI...")
        
        // Get response with streaming
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            cleanupAudioEngine()
            throw TTSError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            print(">>> [ERROR] TTS API error: \(httpResponse.statusCode)")
            cleanupAudioEngine()
            throw TTSError.apiError(httpResponse.statusCode)
        }
        
        print(">>> [TTS] Receiving audio stream...")
        
        // Start tracking time
        audioStartTime = Date()
        
        // Create audio format for PCM
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                        sampleRate: 24000,
                                        channels: 1,
                                        interleaved: true) else {
            cleanupAudioEngine()
            throw TTSError.audioSetupFailed
        }
        
        // Collect audio data
        var audioData = Data()
        var totalBytes = 0
        
        // Stream audio chunks
        for try await byte in asyncBytes {
            audioData.append(byte)
            totalBytes += 1
            
            // When we have enough data, start playing
            if audioData.count >= 48000 { // ~1 second of audio
                playAudioChunk(audioData, format: format)
                audioData.removeAll()
            }
        }
        
        // Play remaining audio
        if !audioData.isEmpty {
            playAudioChunk(audioData, format: format)
        }
        
        print(">>> [TTS] Audio streaming complete - total bytes: \(totalBytes)")
        
        // Calculate duration based on total bytes
        // PCM 24kHz 16-bit mono = 48000 bytes per second
        let durationSeconds = Int(Double(totalBytes) / 48000.0)
        
        // Wait for playback to complete
        try await Task.sleep(nanoseconds: UInt64(durationSeconds) * 1_000_000_000)
        
        // Calculate actual duration
        let actualDuration: Int
        if let startTime = audioStartTime {
            actualDuration = Int(Date().timeIntervalSince(startTime))
        } else {
            actualDuration = durationSeconds
        }
        
        print(">>> [TTS] Audio playback finished - Duration: \(actualDuration)s")
        
        // Clean up the audio engine
        cleanupAudioEngine()
        
        return actualDuration
    }
    
    private func playAudioChunk(_ data: Data, format: AVAudioFormat) {
        guard let playerNode = playerNode else {
            print(">>> [TTS ERROR] Player node is nil!")
            return
        }
        
        let frameCount = AVAudioFrameCount(data.count / 2) // 16-bit = 2 bytes per sample
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print(">>> [ERROR] Failed to create audio buffer")
            return
        }
        
        buffer.frameLength = frameCount
        
        data.withUnsafeBytes { rawBufferPointer in
            guard let address = rawBufferPointer.baseAddress else { return }
            buffer.int16ChannelData?.pointee.initialize(
                from: address.assumingMemoryBound(to: Int16.self),
                count: Int(frameCount)
            )
        }
        
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        
        // Make sure player is playing
        if !playerNode.isPlaying {
            playerNode.play()
            print(">>> [TTS DEBUG] Started player node")
        }
    }
    
    func stopAudio() {
        cleanupAudioEngine()
        print(">>> [TTS] Audio stopped and cleaned up")
    }
}

enum TTSError: Error {
    case invalidResponse
    case apiError(Int)
    case audioSetupFailed
}
