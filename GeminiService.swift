import Foundation
import Combine

class GeminiLiveService: NSObject, ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private let apiKey: String
    private var isConnected = false
    
    // Callbacks
    var onTextChunk: ((String) -> Void)?
    var onAudioChunk: ((Data) -> Void)?
    var onComplete: (() -> Void)?
    var onError: ((Error) -> Void)?
    
    @Published var isStreaming = false
    
    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
    }
    
    func connect(companion: Companion) async throws {
        let urlString = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw GeminiLiveError.invalidURL
        }
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        print(">>> [DEBUG] WebSocket connecting...")
        
        // Wait a moment for connection
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Send setup message
        try await sendSetup(companion: companion)
        
        // Start listening for messages
        Task {
            await listenForMessages()
        }
        
        isConnected = true
        print(">>> [DEBUG] WebSocket connected and setup sent")
    }
    
    private func sendSetup(companion: Companion) async throws {
        let setup: [String: Any] = [
            "setup": [
                "model": "models/gemini-live-2.5-flash-preview",
                "generation_config": [
                    "response_modalities": ["TEXT"],
                    "temperature": 0.9,
                    "max_output_tokens": 200
                ],
                "system_instruction": [
                    "parts": [
                        ["text": companion.systemPrompt]
                    ]
                ]
            ]
        ]
        
        try await sendJSON(setup)
        print(">>> [DEBUG] Setup message sent")
    }
    
    func sendMessage(_ text: String) async throws {
        guard isConnected else {
            throw GeminiLiveError.notConnected
        }
        
        print(">>> [DEBUG] Sending message: \(text)")
        
        let clientContent: [String: Any] = [
            "client_content": [
                "turns": [
                    [
                        "role": "user",
                        "parts": [
                            ["text": text]
                        ]
                    ]
                ],
                "turn_complete": true
            ]
        ]
        
        try await sendJSON(clientContent)
        isStreaming = true
    }
    
    /// Send audio chunk to Gemini Live
    /// Audio must be 16-bit PCM, 16kHz, mono
    func sendAudioChunk(_ audioData: Data) async throws {
        guard isConnected else {
            throw GeminiLiveError.notConnected
        }
        
        // Convert audio data to base64
        let base64Audio = audioData.base64EncodedString()
        
        let realtimeInput: [String: Any] = [
            "realtime_input": [
                "media_chunks": [
                    [
                        "mime_type": "audio/pcm;rate=16000",
                        "data": base64Audio
                    ]
                ]
            ]
        ]
        
        try await sendJSON(realtimeInput)
        
        if !isStreaming {
            isStreaming = true
        }
    }
    
    /// Signal end of audio stream
    func endAudioStream() async throws {
        guard isConnected else {
            throw GeminiLiveError.notConnected
        }
        
        let endStream: [String: Any] = [
            "realtime_input": [
                "audio_stream_end": true
            ]
        ]
        
        try await sendJSON(endStream)
        print(">>> [DEBUG] Audio stream ended")
    }
    
    private func sendJSON(_ json: [String: Any]) async throws {
        let jsonData = try JSONSerialization.data(withJSONObject: json)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
        
        // Only log non-audio messages (audio chunks are too verbose)
        if json["realtime_input"] == nil {
            print(">>> [DEBUG] Sending JSON: \(jsonString)")
        } else {
            print(">>> [DEBUG] Sending audio chunk...")
        }
        
        let message = URLSessionWebSocketTask.Message.string(jsonString)
        try await webSocketTask?.send(message)
    }
    
    private func listenForMessages() async {
        guard let webSocketTask = webSocketTask else { return }
        
        while isConnected {
            do {
                let message = try await webSocketTask.receive()
                
                switch message {
                case .string(let text):
                    print(">>> [DEBUG] Received string message: \(text)")
                    await handleMessage(text)
                    
                case .data(let data):
                    print(">>> [DEBUG] Received binary data, converting to string...")
                    // Convert binary data to string
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print(">>> [DEBUG] Converted to: \(jsonString)")
                        await handleMessage(jsonString)
                    } else {
                        print(">>> [ERROR] Failed to convert binary to string")
                    }
                    
                @unknown default:
                    break
                }
            } catch {
                print(">>> [ERROR] WebSocket receive error: \(error)")
                isConnected = false
                onError?(error)
                break
            }
        }
    }
    
    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print(">>> [ERROR] Failed to parse JSON")
            return
        }
        
        // Check for setup complete
        if json["setupComplete"] != nil {
            print(">>> [DEBUG] Setup complete received")
            return
        }
        
        // Check for server content
        if let serverContent = json["serverContent"] as? [String: Any] {
            print(">>> [DEBUG] Server content received")
            
            // Get model turn
            if let modelTurn = serverContent["modelTurn"] as? [String: Any],
               let parts = modelTurn["parts"] as? [[String: Any]] {
                
                for part in parts {
                    if let text = part["text"] as? String {
                        print(">>> [DEBUG] Got text chunk: \(text)")
                        await MainActor.run {
                            onTextChunk?(text)
                        }
                    }
                }
            }
            
            // Check if turn is complete
            if let turnComplete = serverContent["turnComplete"] as? Bool, turnComplete {
                print(">>> [DEBUG] Turn complete")
                isStreaming = false
                await MainActor.run {
                    onComplete?()
                }
            }
        }
    }
    
    func disconnect() {
        isConnected = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        print(">>> [DEBUG] WebSocket disconnected")
    }
    
    func generateSummary(for messages: [Message]) async throws -> String {
        // For now, create a simple summary
        // TODO: Use a separate API call for summarization
        let recentMessages = messages.suffix(5)
        let summary = recentMessages.map { $0.content }.joined(separator: " ")
        return summary
    }
}

// URLSessionWebSocketDelegate
extension GeminiLiveService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print(">>> [DEBUG] WebSocket opened")
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print(">>> [DEBUG] WebSocket closed: \(closeCode)")
        isConnected = false
    }
}

enum GeminiLiveError: Error {
    case invalidURL
    case notConnected
    case noResponse
}
