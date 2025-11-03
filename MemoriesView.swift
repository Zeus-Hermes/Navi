import SwiftUI
import Combine

struct MemoriesView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel: MemoriesViewModel
    let onMemoriesChanged: (() -> Void)?
    
    init(storageService: StorageService, onMemoriesChanged: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: MemoriesViewModel(storageService: storageService))
        self.onMemoriesChanged = onMemoriesChanged
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if viewModel.memories.isEmpty {
                    // Empty state
                    VStack(spacing: 20) {
                        Image(systemName: "brain")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No memories yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("As you chat, I'll remember important details about you")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        // Nuclear reset button (always available)
                        Button(role: .destructive) {
                            viewModel.showNuclearReset = true
                        } label: {
                            Label("Start Completely Fresh", systemImage: "trash.circle.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.red)
                                .cornerRadius(10)
                        }
                        .padding(.top, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // List of memories
                    List {
                        ForEach(viewModel.memories) { memory in
                            MemoryRow(memory: memory)
                        }
                        .onDelete { offsets in
                            viewModel.deleteMemories(at: offsets)
                            onMemoriesChanged?()
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("What I Know About You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                if !viewModel.memories.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .destructive) {
                            viewModel.showClearAll = true
                        } label: {
                            Text("Clear All")
                                .foregroundColor(.red)
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .destructive) {
                            viewModel.showNuclearReset = true
                        } label: {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .alert("Clear All Memories?", isPresented: $viewModel.showClearAll) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    viewModel.clearAllMemories()
                    onMemoriesChanged?()
                }
            } message: {
                Text("This will delete all stored memories. This action cannot be undone.")
            }
            .alert("Nuclear Reset", isPresented: $viewModel.showNuclearReset) {
                Button("Cancel", role: .cancel) { }
                Button("Reset Everything", role: .destructive) {
                    viewModel.nuclearReset()
                    onMemoriesChanged?()
                    dismiss()
                }
            } message: {
                Text("This will delete ALL memories, conversation history, and start completely fresh. This action cannot be undone.")
            }
        }
    }
}

struct MemoryRow: View {
    let memory: Memory
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Fact
            Text(memory.fact)
                .font(.body)
            
            // Tags
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(memory.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }
                }
            }
            
            // Metadata
            HStack {
                // Importance
                HStack(spacing: 2) {
                    ForEach(0..<memory.importance, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    ForEach(memory.importance..<5, id: \.self) { _ in
                        Image(systemName: "star")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                // Date
                Text(memory.extractedAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 4)
    }
}

@MainActor
class MemoriesViewModel: ObservableObject {
    @Published var memories: [Memory] = []
    @Published var showClearAll = false
    @Published var showNuclearReset = false
    
    private let storageService: StorageService
    
    init(storageService: StorageService) {
        self.storageService = storageService
        loadMemories()
    }
    
    func loadMemories() {
        memories = storageService.loadGlobalMemories()
            .sorted { $0.extractedAt > $1.extractedAt } // Most recent first
    }
    
    func deleteMemories(at offsets: IndexSet) {
        var allMemories = storageService.loadGlobalMemories()
        var blacklistedMemories = storageService.loadBlacklistedMemories()
        
        print(">>> [MEMORY] Before delete: \(allMemories.count) memories")
        
        // Get memories to delete
        let memoriesToDelete = offsets.map { memories[$0] }
        let idsToDelete = memoriesToDelete.map { $0.id }
        
        print(">>> [MEMORY] Deleting \(idsToDelete.count) memories and adding to blacklist")
        
        // Add deleted memories to blacklist
        blacklistedMemories.append(contentsOf: memoriesToDelete)
        storageService.saveBlacklistedMemories(blacklistedMemories)
        
        // Remove from active storage
        allMemories.removeAll { memory in
            idsToDelete.contains(memory.id)
        }
        
        print(">>> [MEMORY] After delete: \(allMemories.count) memories")
        print(">>> [MEMORY] Blacklist now has: \(blacklistedMemories.count) memories")
        
        storageService.saveGlobalMemories(allMemories)
        
        // Update local view
        memories.remove(atOffsets: offsets)
    }
    
    func clearAllMemories() {
        print(">>> [MEMORY] Clearing all memories and adding to blacklist")
        
        // Add all current memories to blacklist
        let allMemories = storageService.loadGlobalMemories()
        var blacklistedMemories = storageService.loadBlacklistedMemories()
        blacklistedMemories.append(contentsOf: allMemories)
        storageService.saveBlacklistedMemories(blacklistedMemories)
        
        // Clear active memories
        storageService.saveGlobalMemories([])
        memories = []
        
        print(">>> [MEMORY] All memories cleared, blacklist has: \(blacklistedMemories.count) memories")
    }
    
    func nuclearReset() {
        print(">>> [MEMORY] 🔥 NUCLEAR RESET - Deleting everything 🔥")
        storageService.clearAllData()
        memories = []
        print(">>> [MEMORY] Reset complete - all data wiped")
    }
}
