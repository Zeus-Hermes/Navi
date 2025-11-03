import Foundation
import AVFoundation

/// Handles audio recording and streaming to both Gemini Live and Whisper
/// - Gemini: Real-time conversation (audio → text response → TTS)
/// - Whisper: Background transcription for memory extraction
class AudioStreamingService: NSObject {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    
    private var isRecording = false
    private var recordingStartTime: Date?
    
    // Accumulated audio for Whisper transcription
    private var whisperAudioBuffer = Data()
    
    // Callbacks
    var onAudioChunk: ((Data) -> Void)?  // For Gemini streaming
    var onRecordingComplete: ((Data) -> Void)?  // For Whisper transcription
    var onError: ((Error) -> Void)?
    
    override init() {
        super.init()
    }
    
    /// Start recording and streaming audio
    func startRecording() throws {
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setActive(true)
        
        // Create audio engine
        audioEngine = AVAudioEngine()
        
        guard let audioEngine = audioEngine else {
            throw AudioStreamingError.engineCreationFailed
        }
        
        inputNode = audioEngine.inputNode
        
        guard let inputNode = inputNode else {
            throw AudioStreamingError.noInputNode
        }
        
        // Get input format
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Define output format: 16-bit PCM, 16kHz, mono (required by Gemini)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioStreamingError.formatCreationFailed
        }
        
        // Create converter
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioStreamingError.converterCreationFailed
        }
        
        print(">>> [AUDIO STREAM] Input format: \(inputFormat)")
        print(">>> [AUDIO STREAM] Output format: \(outputFormat)")
        
        // Reset buffer
        whisperAudioBuffer = Data()
        
        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // Convert to PCM 16kHz format
            guard let convertedBuffer = self.convertBuffer(buffer, using: converter, to: outputFormat) else {
                return
            }
            
            // Get audio data
            let audioData = self.bufferToData(convertedBuffer)
            
            // Store for Whisper
            self.whisperAudioBuffer.append(audioData)
            
            // Stream to Gemini (chunks of audio)
            self.onAudioChunk?(audioData)
        }
        
        // Start engine
        try audioEngine.start()
        
        isRecording = true
        recordingStartTime = Date()
        
        print(">>> [AUDIO STREAM] ✅ Recording started")
    }
    
    /// Stop recording and return full audio for Whisper
    func stopRecording() -> Data {
        guard let audioEngine = audioEngine,
              let inputNode = inputNode else {
            print(">>> [AUDIO STREAM] ⚠️ No engine or input node to stop")
            return Data()
        }
        
        // Remove tap
        inputNode.removeTap(onBus: 0)
        
        // CRITICAL: Actually stop the engine!
        audioEngine.stop()
        
        // CRITICAL: Deactivate the recording audio session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            print(">>> [AUDIO STREAM] Audio session deactivated")
        } catch {
            print(">>> [AUDIO STREAM] Failed to deactivate session: \(error)")
        }
        
        isRecording = false
        
        if let startTime = recordingStartTime {
            let duration = Date().timeIntervalSince(startTime)
            print(">>> [AUDIO STREAM] ✅ Recording stopped. Duration: \(String(format: "%.1f", duration))s")
        }
        
        // Return full audio
        let fullAudio = whisperAudioBuffer
        whisperAudioBuffer = Data()
        
        print(">>> [AUDIO STREAM] Audio buffer size: \(fullAudio.count) bytes")
        
        return fullAudio
    }
    // MARK: - Audio Conversion Helpers
    
    private func convertBuffer(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate)
        
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            print(">>> [AUDIO STREAM] ⚠️ Conversion error: \(error)")
            return nil
        }
        
        return convertedBuffer
    }
    
    private func bufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        let audioBuffer = buffer.int16ChannelData![0]
        let dataSize = Int(buffer.frameLength) * MemoryLayout<Int16>.size
        
        return Data(bytes: audioBuffer, count: dataSize)
    }
    
    func isCurrentlyRecording() -> Bool {
        return isRecording
    }
}

enum AudioStreamingError: Error {
    case engineCreationFailed
    case noInputNode
    case formatCreationFailed
    case converterCreationFailed
    case microphonePermissionDenied
    
    var localizedDescription: String {
        switch self {
        case .engineCreationFailed:
            return "Failed to create audio engine"
        case .noInputNode:
            return "No audio input node available"
        case .formatCreationFailed:
            return "Failed to create audio format"
        case .converterCreationFailed:
            return "Failed to create audio converter"
        case .microphonePermissionDenied:
            return "Microphone permission denied"
        }
    }
}
