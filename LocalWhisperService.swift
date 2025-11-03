import Foundation
import WhisperKit
import AVFoundation

/// Local on-device speech transcription using WhisperKit
/// Zero cost, unlimited usage, complete privacy
class LocalWhisperService {
    private var whisperKit: WhisperKit?
    private var isInitialized = false
    
    // Model configuration
    private let modelVariant: String = "openai_whisper-small" // 483 MB, good accuracy
    
    init() {
        // WhisperKit will be initialized async
        print(">>> [WHISPER] LocalWhisperService created")
    }
    
    /// Initialize WhisperKit model - call this on app launch
    /// This takes ~2-5 seconds, so do it early
    func initialize() async throws {
        guard !isInitialized else {
            print(">>> [WHISPER] Already initialized")
            return
        }
        
        print(">>> [WHISPER] Initializing WhisperKit model: \(modelVariant)")
        let startTime = Date()
        
        do {
            // Initialize WhisperKit with small model
            whisperKit = try await WhisperKit(
                model: modelVariant,
                verbose: true,
                logLevel: .info
            )
            
            let loadTime = Date().timeIntervalSince(startTime)
            isInitialized = true
            
            print(">>> [WHISPER] ✅ Model loaded successfully in \(String(format: "%.2f", loadTime))s")
        } catch {
            print(">>> [WHISPER] ❌ Failed to initialize: \(error)")
            throw WhisperError.initializationFailed(error.localizedDescription)
        }
    }
    
    /// Transcribe audio file to text
    /// - Parameter audioPath: Full path to audio file (m4a, wav, mp3)
    /// - Returns: Transcribed text
    func transcribe(audioPath: String) async throws -> String {
        guard isInitialized, let whisperKit = whisperKit else {
            throw WhisperError.notInitialized
        }
        
        print(">>> [WHISPER] Transcribing: \(audioPath)")
        let startTime = Date()
        
        do {
            // Transcribe the audio file
            let transcriptionResults = try await whisperKit.transcribe(audioPath: audioPath)
            
            let transcribeTime = Date().timeIntervalSince(startTime)
            
            // WhisperKit returns array of results, get the first one
            guard let firstResult = transcriptionResults.first else {
                throw WhisperError.emptyTranscription
            }
            
            let text = firstResult.text
            
            print(">>> [WHISPER] ✅ Transcribed in \(String(format: "%.2f", transcribeTime))s")
            print(">>> [WHISPER] Result: \(text)")
            
            guard !text.isEmpty else {
                throw WhisperError.emptyTranscription
            }
            
            return text
            
        } catch {
            print(">>> [WHISPER] ❌ Transcription failed: \(error)")
            throw WhisperError.transcriptionFailed(error.localizedDescription)
        }
    }
    
    /// Transcribe audio file with detailed results
    /// Useful for debugging and testing
    func transcribeDetailed(audioPath: String) async throws -> TranscriptionResult {
        guard isInitialized, let whisperKit = whisperKit else {
            throw WhisperError.notInitialized
        }
        
        print(">>> [WHISPER] Transcribing (detailed): \(audioPath)")
        let startTime = Date()
        
        do {
            let transcriptionResults = try await whisperKit.transcribe(audioPath: audioPath)
            let transcribeTime = Date().timeIntervalSince(startTime)
            
            // Get first result
            guard let firstResult = transcriptionResults.first else {
                throw WhisperError.emptyTranscription
            }
            
            let text = firstResult.text
            let segments = firstResult.segments
            
            print(">>> [WHISPER] ✅ Detailed transcription complete")
            print(">>> [WHISPER] Text: \(text)")
            print(">>> [WHISPER] Segments: \(segments.count)")
            print(">>> [WHISPER] Time: \(String(format: "%.2f", transcribeTime))s")
            
            return TranscriptionResult(
                text: text,
                segments: segments.map { segment in
                    TranscriptionSegment(
                        text: segment.text,
                        start: segment.start,
                        end: segment.end
                    )
                },
                duration: transcribeTime
            )
            
        } catch {
            print(">>> [WHISPER] ❌ Detailed transcription failed: \(error)")
            throw WhisperError.transcriptionFailed(error.localizedDescription)
        }
    }
    
    /// Check if service is ready to transcribe
    func isReady() -> Bool {
        return isInitialized && whisperKit != nil
    }
    
    /// Get model information
    func getModelInfo() -> String {
        return modelVariant
    }
}

// MARK: - Error Types

enum WhisperError: Error, LocalizedError {
    case notInitialized
    case initializationFailed(String)
    case transcriptionFailed(String)
    case emptyTranscription
    case invalidAudioFile
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "WhisperKit not initialized. Call initialize() first."
        case .initializationFailed(let details):
            return "Failed to initialize WhisperKit: \(details)"
        case .transcriptionFailed(let details):
            return "Transcription failed: \(details)"
        case .emptyTranscription:
            return "Transcription resulted in empty text"
        case .invalidAudioFile:
            return "Invalid or corrupted audio file"
        }
    }
}

// MARK: - Result Types

struct TranscriptionResult {
    let text: String
    let segments: [TranscriptionSegment]
    let duration: TimeInterval
    
    var wordCount: Int {
        return text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
}

struct TranscriptionSegment {
    let text: String
    let start: Float
    let end: Float
    
    var duration: Float {
        return end - start
    }
}

// MARK: - Testing Helpers

extension LocalWhisperService {
    /// Test transcription with a sample phrase
    /// For debugging and verification
    func testTranscription(testAudioPath: String) async {
        print(">>> [WHISPER] 🧪 Running test transcription")
        
        do {
            // Initialize if needed
            if !isInitialized {
                try await initialize()
            }
            
            // Transcribe
            let result = try await transcribeDetailed(audioPath: testAudioPath)
            
            // Print results
            print(">>> [WHISPER] 🧪 Test Results:")
            print(">>> [WHISPER] 📝 Text: \(result.text)")
            print(">>> [WHISPER] ⏱️ Duration: \(String(format: "%.2f", result.duration))s")
            print(">>> [WHISPER] 📊 Word count: \(result.wordCount)")
            print(">>> [WHISPER] 🔢 Segments: \(result.segments.count)")
            
            if result.segments.count > 0 {
                print(">>> [WHISPER] 📍 First segment: \(result.segments[0].text)")
            }
            
            print(">>> [WHISPER] ✅ Test passed!")
            
        } catch {
            print(">>> [WHISPER] ❌ Test failed: \(error)")
        }
    }
}
