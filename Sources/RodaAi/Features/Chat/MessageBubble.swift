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
                    Label("chat.assistant", systemImage: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(message.content)
                    .padding(12)
                    .modifier(BubbleBackgroundModifier(isUser: isUser))
                    .textSelection(.enabled)
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

/// Fundo da bolha: usuario = accent opaco, assistente = glass translucido.
private struct BubbleBackgroundModifier: ViewModifier {
    let isUser: Bool

    func body(content: Content) -> some View {
        if isUser {
            content
                .background(Color.accentColor.gradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
        } else {
            if #available(iOS 26, macOS 26, *) {
                content
                    .foregroundStyle(.primary)
                    .glassEffect(in: .rect(cornerRadius: 18))
            } else {
                content
                    .background(Color(.secondarySystemBackground))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}
