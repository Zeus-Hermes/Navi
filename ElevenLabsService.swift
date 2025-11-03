import Foundation
import AVFoundation

class ElevenLabsService: NSObject {
    private let apiKey: String
    private var webSocketTask: URLSessionWebSocketTask?
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var isStreamActive = false
    
    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        
        if let engine = audioEngine, let player = playerNode {
            engine.attach(player)
            
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
            } catch {
                print("Failed to start audio engine: \(error)")
            }
        }
    }
    
    // Start a new stream session
    func startStream(voiceID: String) async throws {
        let urlString = "wss://api.elevenlabs.io/v1/text-to-speech/\(voiceID)/stream-input?model_id=eleven_flash_v2_5&output_format=pcm_24000"
        
        guard let url = URL(string: urlString) else {
            throw ElevenLabsError.invalidURL
        }
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        print(">>> [DEBUG] ElevenLabs WebSocket opened")
        
        // SET THIS FIRST!
        isStreamActive = true
        
        // Then start listening
        Task {
            await listenForAudio()
        }
        
        // Send initial config
        let initialMessage: [String: Any] = [
            "text": " ",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.8
            ],
            "xi_api_key": apiKey
        ]
        
        try await sendWebSocketMessage(initialMessage)
    }
    
    // Send a text chunk to the active stream
    func sendTextChunk(_ text: String) async throws {
        guard isStreamActive else {
            print(">>> [ERROR] Stream not active")
            return
        }
        
        let textMessage: [String: Any] = [
            "text": text + " "
        ]
        
        try await sendWebSocketMessage(textMessage)
    }
    
    // End the stream
    func endStream() async throws {
        guard isStreamActive else { return }
        
        let endMessage: [String: Any] = ["text": ""]
        try await sendWebSocketMessage(endMessage)
        
        print(">>> [DEBUG] ElevenLabs stream ended")
        
        // Wait for final audio
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        isStreamActive = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }
    
    private func sendWebSocketMessage(_ message: [String: Any]) async throws {
        let jsonData = try JSONSerialization.data(withJSONObject: message)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
        
        try await webSocketTask?.send(.string(jsonString))
    }
    
    private func listenForAudio() async {
        guard let webSocketTask = webSocketTask else {
            print(">>> [ERROR] No WebSocket task!")
            return
        }
        
        print(">>> [DEBUG] ElevenLabs listening for audio...")
        
        while isStreamActive {
            do {
                print(">>> [DEBUG] ElevenLabs waiting for message...")
                let message = try await webSocketTask.receive()
                print(">>> [DEBUG] ElevenLabs message received!")
                
                switch message {
                case .string(let text):
                    print(">>> [DEBUG] ElevenLabs received: \(text)")
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        
                        print(">>> [DEBUG] ElevenLabs JSON parsed")
                        
                        if let audioBase64 = json["audio"] as? String,
                           let audioData = Data(base64Encoded: audioBase64) {
                            print(">>> [DEBUG] Playing audio chunk: \(audioData.count) bytes")
                            playAudioChunk(audioData)
                        }
                        
                        if let isFinal = json["isFinal"] as? Bool, isFinal {
                            print(">>> [DEBUG] ElevenLabs final chunk received")
                            break
                        }
                    }
                    
                case .data(let data):
                    print(">>> [DEBUG] ElevenLabs binary data: \(data.count) bytes")
                    playAudioChunk(data)
                    
                @unknown default:
                    break
                }
            } catch {
                print(">>> [ERROR] ElevenLabs WebSocket error: \(error)")
                isStreamActive = false
                break
            }
        }
        
        print(">>> [DEBUG] ElevenLabs listen loop ended")
    }
    
    private func playAudioChunk(_ data: Data) {
        guard let playerNode = playerNode,
              let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                        sampleRate: 24000,
                                        channels: 1,
                                        interleaved: true) else {
            return
        }
        
        let frameCount = AVAudioFrameCount(data.count / 2)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }
        
        buffer.frameLength = frameCount
        
        data.withUnsafeBytes { rawBufferPointer in
            guard let address = rawBufferPointer.baseAddress else { return }
            buffer.int16ChannelData?.pointee.initialize(from: address.assumingMemoryBound(to: Int16.self),
                                                       count: Int(frameCount))
        }
        
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }
    
    func stopAudio() {
        isStreamActive = false
        playerNode?.stop()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }
}

enum ElevenLabsError: Error {
    case requestFailed
    case invalidVoiceID
    case invalidURL
}
