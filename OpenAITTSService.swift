import Foundation
import AVFoundation

class OpenAITTSService {
    private let apiKey: String
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioStartTime: Date?
    
    init(apiKey: String) {
        self.apiKey = apiKey
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        
        if let engine = audioEngine, let player = playerNode {
            engine.attach(player)
            
            // PCM format: 24kHz, 16-bit, mono (matches OpenAI TTS output)
            let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                      sampleRate: 24000,
                                      channels: 1,
                                      interleaved: true)
            
            if let format = format {
                engine.connect(player, to: engine.mainMixerNode, format: format)
            }
            
            do {
                try engine.start()
                player.play()
                print(">>> [TTS] Audio engine started")
            } catch {
                print(">>> [ERROR] Failed to start audio engine: \(error)")
            }
        }
    }
    
    /// Generate speech from text and play it
    /// Returns the duration in seconds after audio finishes
    func generateAndPlaySpeech(text: String, companion: Companion) async throws -> Int {
        print(">>> [TTS] Generating speech for: \(text.prefix(50))...")
        
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
            throw TTSError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            print(">>> [ERROR] TTS API error: \(httpResponse.statusCode)")
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
            throw TTSError.audioSetupFailed
        }
        
        // Collect audio data
        var audioData = Data()
        
        // Stream audio chunks
        for try await byte in asyncBytes {
            audioData.append(byte)
            
            // When we have enough data, start playing
            if audioData.count >= 48000 && playerNode?.isPlaying == true { // ~1 second of audio
                playAudioChunk(audioData, format: format)
                audioData.removeAll()
            }
        }
        
        // Play remaining audio
        if !audioData.isEmpty {
            playAudioChunk(audioData, format: format)
        }
        
        print(">>> [TTS] Audio streaming complete")
        
        // Wait for audio to finish playing
        // Calculate duration based on data size
        // PCM 24kHz 16-bit mono = 48000 bytes per second
        let totalBytes = audioData.count
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
        
        return actualDuration
    }
    
    private func playAudioChunk(_ data: Data, format: AVAudioFormat) {
        guard let playerNode = playerNode else { return }
        
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
    }
    
    func stopAudio() {
        playerNode?.stop()
        print(">>> [TTS] Audio stopped")
    }
}

enum TTSError: Error {
    case invalidResponse
    case apiError(Int)
    case audioSetupFailed
}
