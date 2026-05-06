import SwiftUI

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String

    static func user(_ text: String) -> ChatMessage { .init(role: .user, text: text) }
    static func assistant(_ text: String) -> ChatMessage { .init(role: .assistant, text: text) }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .assistant {
                bubble(alignment: .leading, fill: FamilyAppStyle.listCardFill, stroke: FamilyAppStyle.cardStroke)
                Spacer(minLength: 24)
            } else {
                Spacer(minLength: 24)
                bubble(alignment: .trailing, fill: FamilyAppStyle.accent.opacity(0.16), stroke: FamilyAppStyle.accent.opacity(0.22))
            }
        }
        .padding(.horizontal, 16)
    }

    private func bubble(alignment: Alignment, fill: Color, stroke: Color) -> some View {
        Text(message.text)
            .font(.body)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(12)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
    }
}

