// Sources/RodaAi/Features/Chat/ChatView.swift
import SwiftUI
import RodaAiCore

struct ChatView: View {
    @State var viewModel: ChatViewModel

    /// File processor injetado para anexos (pode usar FileProcessor real ou mock).
    var fileProcessor: any FileTextExtractor = FileProcessor()

    var body: some View {
        VStack(spacing: 0) {
            // Mensagens
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if viewModel.messages.isEmpty {
                            emptyStateView
                                .padding(.top, 60)
                        } else {
                            ForEach(Array(viewModel.messages.enumerated()), id: \.offset) { index, message in
                                MessageBubble(message: message)
                                    .id(index)
                            }
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
                    Button("chat.action.retry") {
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

            // Compositor (com anexos de arquivo + imagem)
            MessageComposer(
                isStreaming: viewModel.chatState.isStreaming,
                onSend: { text, attachedText, imageData in
                    Task {
                        let fullText: String
                        if let attached = attachedText, !attached.isEmpty {
                            fullText = "Documento anexado:\n\(attached)\n\n\(text)"
                        } else {
                            fullText = text
                        }
                        await viewModel.send(fullText, imageData: imageData)
                    }
                },
                onStop: {
                    viewModel.stopGeneration()
                },
                fileProcessor: fileProcessor
            )
        }
        .navigationTitle("chat.title")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "message")
                .font(.system(size: 48))
                .foregroundStyle(ColorPalette.textTertiary)
            Text("chat.empty.title")
                .font(.rodaHeadline)
                .foregroundStyle(ColorPalette.textSecondary)
            Text("chat.empty.subtitle")
                .font(.rodaCaption)
                .foregroundStyle(ColorPalette.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}
