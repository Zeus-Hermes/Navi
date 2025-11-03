import SwiftUI
import Combine

struct ContentView: View {
    var body: some View {
        TabView {
            ChatView(companion: .theo)
                .tabItem {
                    Label("Chat", systemImage: "message")
                }
            
            VoiceRecordingTestView() // ← Add this
                .tabItem {
                    Label("Voice Test", systemImage: "mic")
                }
        }
    }
}
