import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @State private var messageText = ""
    @State private var showCompanionSelector = false
    @State private var showClearConfirmation = false
    @State private var showMemories = false
    
    init(companion: Companion = .theo) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(companion: companion))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(viewModel.currentCompanion.rawValue)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Voice quota display
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text(viewModel.voiceQuotaRemaining)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                
                // Clear chat button
                Button(action: {
                    showClearConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .font(.title3)
                        .foregroundColor(.red)
                }
                .alert("Clear Chat?", isPresented: $showClearConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Clear", role: .destructive) {
                        viewModel.clearChatView()
                    }
                } message: {
                    Text("This will clear the visible messages but keep your conversation history and memories.")
                }
                
                // Memories button
                Button(action: {
                    showMemories = true
                }) {
                    Image(systemName: "brain")
                        .font(.title3)
                        .foregroundColor(.purple)
                }
                
                Button(action: {
                    showCompanionSelector = true
                }) {
                    Image(systemName: "person.2.fill")
                        .font(.title3)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            
            // Messages
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    // Upgrade prompt banner
                    if viewModel.showUpgradePrompt {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "waveform.slash")
                                    .foregroundColor(.orange)
                                Text("You've used your daily voice time!")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Button(action: {
                                    viewModel.showUpgradePrompt = false
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            Text("\(viewModel.currentCompanion.rawValue) can still chat via text (unlimited).")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            Button(action: {
                                print(">>> [UI] Upgrade button tapped")
                            }) {
                                Text("Upgrade to 90 min/day")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            
                            if viewModel.isLoading {
                                HStack {
                                    ProgressView()
                                        .padding(.leading)
                                    Text("Thinking...")
                                        .foregroundColor(.gray)
                                    Spacer()
                                }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        if let lastMessage = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            // Recording indicator
            if viewModel.isRecordingVoice {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .opacity(0.8)
                    
                    Text("Recording...")
                        .font(.subheadline)
                        .foregroundColor(.red)
                    
                    Text(formatDuration(viewModel.recordingDuration))
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .monospacedDigit()
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
            }
            
            // Input bar
            HStack(spacing: 12) {
                TextField("Message \(viewModel.currentCompanion.rawValue)...", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(viewModel.isLoading || viewModel.isRecordingVoice)
                
                // Voice button
                Button(action: {
                    if viewModel.isRecordingVoice {
                        Task {
                            await viewModel.stopVoiceRecording()
                        }
                    } else {
                        viewModel.startVoiceRecording()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(viewModel.isRecordingVoice ? Color.red : Color.blue)
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: viewModel.isRecordingVoice ? "stop.fill" : "mic.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 20))
                    }
                }
                .disabled(viewModel.isLoading && !viewModel.isRecordingVoice)
                
                // Send button
                if !viewModel.isRecordingVoice && !messageText.isEmpty {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .sheet(isPresented: $showCompanionSelector) {
            CompanionSelectorView(
                currentCompanion: viewModel.currentCompanion,
                onSelect: { companion in
                    viewModel.switchCompanion(to: companion)
                    showCompanionSelector = false
                }
            )
        }
        .sheet(isPresented: $showMemories) {
            MemoriesView(storageService: viewModel.storageService) {
                Task {
                    await viewModel.reconnectGemini()
                }
            }
        }
    }
    
    private func sendMessage() {
        let text = messageText
        messageText = ""
        
        Task {
            await viewModel.sendMessage(text)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct MessageBubble: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            Text(message.content)
                .padding(12)
                .background(message.isUser ? Color.blue : Color(.systemGray5))
                .foregroundColor(message.isUser ? .white : .primary)
                .cornerRadius(16)
                .frame(maxWidth: 280, alignment: message.isUser ? .trailing : .leading)
            
            if !message.isUser {
                Spacer()
            }
        }
    }
}
