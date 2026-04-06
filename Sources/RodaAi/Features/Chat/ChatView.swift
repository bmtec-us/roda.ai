// Sources/RodaAi/Features/Chat/ChatView.swift
import SwiftUI
import RodaAiCore

struct ChatView: View {
    @State var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Mensagens
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(viewModel.messages.enumerated()), id: \.offset) { index, message in
                            MessageBubble(message: message)
                                .id(index)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, newCount in
                    withAnimation {
                        proxy.scrollTo(newCount - 1, anchor: .bottom)
                    }
                }
            }

            // Erro (ref: data-flows.md "Fluxo de Erro")
            if let errorMessage = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.caption)
                    Button("Tentar novamente") {
                        viewModel.resetError()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }

            Divider()

            // Compositor
            MessageComposer(
                isStreaming: viewModel.chatState.isStreaming,
                onSend: { text in
                    Task { await viewModel.send(text) }
                },
                onStop: {
                    viewModel.stopGeneration()
                }
            )
        }
        .navigationTitle("Chat")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
