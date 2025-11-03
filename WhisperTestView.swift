import SwiftUI
import Combine

/// Simple test view for Phase 1 Whisper testing
/// Add this to your project and navigate to it to test transcription
struct WhisperTestView: View {
    @StateObject private var viewModel = WhisperTestViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    // Status Section
                    VStack(spacing: 10) {
                        Text("Whisper Status")
                            .font(.headline)
                        
                        HStack {
                            Circle()
                                .fill(viewModel.isInitialized ? Color.green : Color.red)
                                .frame(width: 12, height: 12)
                            Text(viewModel.isInitialized ? "Ready" : "Not Initialized")
                                .font(.subheadline)
                        }
                        
                        if let modelInfo = viewModel.modelInfo {
                            Text("Model: \(modelInfo)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Initialize Button
                    Button(action: {
                        Task {
                            await viewModel.initialize()
                        }
                    }) {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(viewModel.isInitialized ? "Reinitialize" : "Initialize Whisper")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(viewModel.isLoading)
                    
                    Divider()
                    
                    // Test File Input
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Test Audio File")
                            .font(.headline)
                        
                        TextField("Audio file name (e.g., test1.m4a)", text: $viewModel.testFileName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Text("Place file in app bundle or document directory")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    // Transcribe Button
                    Button(action: {
                        Task {
                            await viewModel.transcribe()
                        }
                    }) {
                        HStack {
                            if viewModel.isTranscribing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text("Transcribe")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.isInitialized ? Color.green : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!viewModel.isInitialized || viewModel.isTranscribing)
                    
                    // Results Section
                    if !viewModel.transcriptionResult.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Transcription Result")
                                .font(.headline)
                            
                            Text(viewModel.transcriptionResult)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                            
                            if let duration = viewModel.transcriptionDuration {
                                Text("Time: \(String(format: "%.2f", duration))s")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    
                    // Error Section
                    if let error = viewModel.errorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Error")
                                .font(.headline)
                                .foregroundColor(.red)
                            
                            Text(error)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Whisper Test")
        }
    }
}

@MainActor
class WhisperTestViewModel: ObservableObject {
    @Published var isInitialized = false
    @Published var isLoading = false
    @Published var isTranscribing = false
    @Published var transcriptionResult = ""
    @Published var transcriptionDuration: Double?
    @Published var errorMessage: String?
    @Published var testFileName = "test1.m4a"
    @Published var modelInfo: String?
    
    private let whisperService = LocalWhisperService()
    
    func initialize() async {
        isLoading = true
        errorMessage = nil
        
        print(">>> [TEST] Initializing Whisper...")
        
        do {
            try await whisperService.initialize()
            isInitialized = true
            modelInfo = whisperService.getModelInfo()
            print(">>> [TEST] ✅ Initialization successful")
        } catch {
            errorMessage = "Initialization failed: \(error.localizedDescription)"
            print(">>> [TEST] ❌ Initialization failed: \(error)")
        }
        
        isLoading = false
    }
    
    func transcribe() async {
        guard isInitialized else {
            errorMessage = "Please initialize first"
            return
        }
        
        isTranscribing = true
        errorMessage = nil
        transcriptionResult = ""
        transcriptionDuration = nil
        
        print(">>> [TEST] Looking for file: \(testFileName)")
        
        // Try to find the file
        let audioPath = findAudioFile(named: testFileName)
        
        guard let audioPath = audioPath else {
            errorMessage = "Audio file '\(testFileName)' not found. Please add it to the app bundle or documents directory."
            isTranscribing = false
            print(">>> [TEST] ❌ File not found")
            return
        }
        
        print(">>> [TEST] Found file at: \(audioPath)")
        print(">>> [TEST] Starting transcription...")
        
        let startTime = Date()
        
        do {
            let text = try await whisperService.transcribe(audioPath: audioPath)
            let duration = Date().timeIntervalSince(startTime)
            
            transcriptionResult = text
            transcriptionDuration = duration
            
            print(">>> [TEST] ✅ Transcription successful")
            print(">>> [TEST] Result: \(text)")
            print(">>> [TEST] Duration: \(String(format: "%.2f", duration))s")
            
        } catch {
            errorMessage = "Transcription failed: \(error.localizedDescription)"
            print(">>> [TEST] ❌ Transcription failed: \(error)")
        }
        
        isTranscribing = false
    }
    
    private func findAudioFile(named fileName: String) -> String? {
        // Try bundle first
        if let bundlePath = Bundle.main.path(forResource: fileName.replacingOccurrences(of: ".\(fileName.split(separator: ".").last ?? "")", with: ""), ofType: String(fileName.split(separator: ".").last ?? "")) {
            return bundlePath
        }
        
        // Try documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filePath = documentsPath.appendingPathComponent(fileName).path
        
        if FileManager.default.fileExists(atPath: filePath) {
            return filePath
        }
        
        return nil
    }
}

// Preview
#Preview {
    WhisperTestView()
}
