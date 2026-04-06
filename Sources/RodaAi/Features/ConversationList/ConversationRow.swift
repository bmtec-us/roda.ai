// Sources/RodaAi/Features/ConversationList/ConversationRow.swift
import SwiftUI
import RodaAiCore

struct ConversationRow: View {
    let conversation: ConversationSummary

    private let dateFormatter = RelativeDateFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if conversation.title.isEmpty {
                    Text("chat.action.newConversation")
                        .font(.headline)
                        .lineLimit(1)
                } else {
                    Text(conversation.title)
                        .font(.headline)
                        .lineLimit(1)
                }

                Spacer()

                Text(dateFormatter.string(from: conversation.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let preview = conversation.lastMessagePreview {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                // Modelo badge
                HStack(spacing: 3) {
                    Image(systemName: "cpu")
                        .font(.caption2)
                    Text(conversation.modelIdentifier)
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)

                Spacer()

                // Contagem de mensagens
                if conversation.messageCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.caption2)
                        Text("\(conversation.messageCount)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
