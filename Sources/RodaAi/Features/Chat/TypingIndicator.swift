// Sources/RodaAi/Features/Chat/TypingIndicator.swift
//
// Indicador de "Assistente esta digitando..." exibido enquanto o ChatViewModel
// esta em estado .loading (entre o send e o primeiro token chegar).
//
// Visual: bolha do assistente com 3 dots animados.
import SwiftUI

struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("chat.assistant")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                AnimatedDots(reduceMotion: reduceMotion, color: .secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            Spacer(minLength: 60)
        }
    }

    private var bubbleBackground: Color {
        #if os(iOS)
        return Color(.systemGray6)
        #else
        return Color.gray.opacity(0.15)
        #endif
    }
}

#Preview {
    TypingIndicator()
        .padding()
}
