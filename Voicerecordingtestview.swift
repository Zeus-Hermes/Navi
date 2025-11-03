import SwiftUI
import AVFoundation
import Combine

/// Simple voice recording test - just record and see transcription
/// No chat, no Gemini, pure transcription testing
struct VoiceRecordingTestView: View {
    @StateObject private var viewModel = VoiceRecordingTestViewModel()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 40) {
                Spacer()
                
                // Status
                VStack(spacing: 10) {
                    if viewModel.isInitializing {
                        ProgressView()
                        Text("Loading Whisper model...")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    } else if !viewModel.isWhisperReady {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("Whisper not initialized")
                            .font(.headline)
                    } else if viewModel.isRecording {
                        // Recording indicator
                        Circle()
                            .fill(Color.red)
                            .frame(width: 20, height: 20)
                            .opacity(viewModel.recordingPulse ? 1.0 : 0.3)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: viewModel.recordingPulse)
                        
                        Text("Recording...")
                            .font(.headline)
                            .foregroundColor(.red)
                        
                        Text(viewModel.recordingDuration)
                            .font(.title2)
                            .monospacedDigit()
                    } else if viewModel.isTranscribing {
                        ProgressView()
                        Text("Transcribing...")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Tap to record")
                            .font(.headline)
                    }
                }
                
                // Big record button
                Button(action: {
                    viewModel.toggleRecording()
                }) {
                    ZStack {
                        Circle()
                            .fill(viewModel.isRecording ? Color.red : Color.blue)
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                    }
                }
                .disabled(!viewModel.isWhisperReady || viewModel.isTranscribing)
                
                Spacer()
                
                // Transcription result
                if !viewModel.transcription.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Transcription:")
                                .font(.headline)
                            Spacer()
                            if let duration = viewModel.transcriptionTime {
                                Text("\(String(format: "%.1f", duration))s")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        ScrollView {
                            Text(viewModel.transcription)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                        }
                        .frame(maxHeight: 200)
                    }
                    .padding()
                }
                
                // Error message
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Voice Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.initialize()
            }
        }
    }
}

@MainActor
class VoiceRecordingTestViewModel: ObservableObject {
    @Published var isWhisperReady = false
    @Published var isInitializing = true
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var transcription = ""
    @Published var transcriptionTime: Double?
    @Published var errorMessage: String?
    @Published var recordingDuration = "0:00"
    @Published var recordingPulse = false
    
    private let whisperService = LocalWhisperService()
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    
    func initialize() {
        Task {
            do {
                // Request mic permission
                let permission = await requestMicrophonePermission()
                guard permission else {
                    errorMessage = "Microphone permission denied"
                    isInitializing = false
                    return
                }
                
                // Initialize Whisper
                try await whisperService.initialize()
                isWhisperReady = true
                print(">>> [VOICE TEST] Ready")
                
            } catch {
                errorMessage = "Failed to initialize: \(error.localizedDescription)"
                print(">>> [VOICE TEST] Error: \(error)")
            }
            
            isInitializing = false
        }
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        errorMessage = nil
        transcription = ""
        transcriptionTime = nil
        
        // Configure audio session FIRST
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true)
            print(">>> [VOICE TEST] Audio session configured")
        } catch {
            errorMessage = "Failed to setup audio session: \(error.localizedDescription)"
            print(">>> [VOICE TEST] Audio session error: \(error)")
            return
        }
        
        // Use WAV format - much simpler and always works
        let audioFilename = getDocumentsDirectory().appendingPathComponent("test_recording.wav")
        
        // Delete old file if exists
        try? FileManager.default.removeItem(at: audioFilename)
        print(">>> [VOICE TEST] Recording to: \(audioFilename.path)")
        
        // Simple linear PCM settings - always works
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            
            guard let recorder = audioRecorder else {
                throw NSError(domain: "VoiceTest", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to create recorder"])
            }
            
            // Prepare
            let prepared = recorder.prepareToRecord()
            print(">>> [VOICE TEST] Recorder prepared: \(prepared)")
            
            if !prepared {
                throw NSError(domain: "VoiceTest", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare recorder"])
            }
            
            // Start recording
            let success = recorder.record()
            print(">>> [VOICE TEST] Recording started: \(success)")
            print(">>> [VOICE TEST] Recorder isRecording: \(recorder.isRecording)")
            
            if !success {
                throw NSError(domain: "VoiceTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "Recorder.record() returned false - check mic permissions in Settings"])
            }
            
            isRecording = true
            recordingStartTime = Date()
            recordingPulse = true
            
            // Start timer for duration display
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.updateRecordingDuration()
            }
            
            print(">>> [VOICE TEST] ✅ Recording started successfully")
            
        } catch {
            errorMessage = "Recording failed: \(error.localizedDescription)"
            print(">>> [VOICE TEST] ❌ Recording error: \(error)")
        }
    }
    
    private func stopRecording() {
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        recordingPulse = false
        
        print(">>> [VOICE TEST] Recording stopped")
        
        // Transcribe
        Task {
            await transcribeRecording()
        }
    }
    
    private func transcribeRecording() async {
        isTranscribing = true
        
        let audioFilename = getDocumentsDirectory().appendingPathComponent("test_recording.wav")
        
        print(">>> [VOICE TEST] Transcribing: \(audioFilename.path)")
        
        // Check if file exists
        if !FileManager.default.fileExists(atPath: audioFilename.path) {
            errorMessage = "Recording file not found"
            isTranscribing = false
            return
        }
        
        // Check file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: audioFilename.path),
           let fileSize = attrs[.size] as? UInt64 {
            print(">>> [VOICE TEST] File size: \(fileSize) bytes")
            
            if fileSize == 0 {
                errorMessage = "Recording file is empty - mic may not be working"
                isTranscribing = false
                return
            }
        }
        
        let startTime = Date()
        
        do {
            let text = try await whisperService.transcribe(audioPath: audioFilename.path)
            let duration = Date().timeIntervalSince(startTime)
            
            transcription = text
            transcriptionTime = duration
            
            print(">>> [VOICE TEST] ✅ Transcribed: \(text)")
            print(">>> [VOICE TEST] Time: \(String(format: "%.2f", duration))s")
            
        } catch {
            errorMessage = "Transcription failed: \(error.localizedDescription)"
            print(">>> [VOICE TEST] ❌ Error: \(error)")
        }
        
        isTranscribing = false
    }
    
    private func updateRecordingDuration() {
        guard let startTime = recordingStartTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        recordingDuration = String(format: "%d:%02d", minutes, seconds)
    }
    
    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

#Preview {
    VoiceRecordingTestView()
}
