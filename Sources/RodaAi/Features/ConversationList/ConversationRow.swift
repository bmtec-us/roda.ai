// Sources/RodaAi/Features/ConversationList/ConversationRow.swift
import SwiftUI
import RodaAiCore

struct ConversationRow: View {
    let conversation: ConversationSummary

    private let dateFormatter = RelativeDateFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(conversation.title.isEmpty ? "Nova conversa" : conversation.title)
                    .font(.headline)
                    .lineLimit(1)

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

            HStack {
                Image(systemName: "cpu")
                    .font(.caption2)
                Text(conversation.modelIdentifier)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
