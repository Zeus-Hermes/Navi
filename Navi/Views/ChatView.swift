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
            
            // Input bar
            HStack {
                TextField("Message \(viewModel.currentCompanion.rawValue)...", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(viewModel.isLoading)
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(messageText.isEmpty ? .gray : .blue)
                }
                .disabled(messageText.isEmpty || viewModel.isLoading)
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
                // Reconnect when memories change
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
