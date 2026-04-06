// Sources/RodaAi/Features/Chat/MessageBubble.swift
import SwiftUI
import RodaAiCore

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !isUser {
                    Text("Assistente")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(message.content)
                    .padding(12)
                    .background(isUser ? Color.accentColor : MessageBubble.bubbleBackground)
                    .foregroundStyle(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .textSelection(.enabled)
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    /// Cor de fundo da bolha do assistente. Adapta-se entre iOS e macOS.
    private static var bubbleBackground: Color {
        #if os(iOS)
        return Color(.systemGray6)
        #else
        return Color.gray.opacity(0.15)
        #endif
    }
}
