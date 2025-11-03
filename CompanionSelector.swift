import SwiftUI

struct CompanionSelectorView: View {
    let currentCompanion: Companion
    let onSelect: (Companion) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Choose Your Companion")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top, 40)
                
                // Theo
                CompanionCard(
                    companion: .theo,
                    isSelected: currentCompanion == .theo,
                    description: "Witty, sarcastic, calls you out on your BS (lovingly)",
                    onTap: {
                        onSelect(.theo)
                    }
                )
                
                // Maven
                CompanionCard(
                    companion: .maven,
                    isSelected: currentCompanion == .maven,
                    description: "Warm, supportive, gentle guidance",
                    onTap: {
                        onSelect(.maven)
                    }
                )
                
                Spacer()
            }
            .padding()
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
    }
}

struct CompanionCard: View {
    let companion: Companion
    let isSelected: Bool
    let description: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(companion.rawValue)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                    }
                }
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
