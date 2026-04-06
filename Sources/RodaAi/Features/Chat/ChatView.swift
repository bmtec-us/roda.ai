// Sources/RodaAi/Features/Chat/ChatView.swift
import SwiftUI
import RodaAiCore

struct ChatView: View {
    @State var viewModel: ChatViewModel
    @Environment(AppDependencies.self) private var deps

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
                            // Typing indicator durante .loading (entre send e primeiro token)
                            if case .loading = viewModel.chatState {
                                TypingIndicator()
                                    .id("typingIndicator")
                                    .transition(.opacity)
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
                ErrorBanner(
                    message: errorMessage,
                    onRetry: { viewModel.resetError() },
                    onDismiss: { viewModel.resetError() }
                )
                .padding(.vertical, 6)
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
        .toolbar {
            ToolbarItem(placement: .principal) {
                modelSwitcherMenu
            }
        }
    }

    // MARK: - Model Switcher Menu

    /// Menu no toolbar mostrando modelo ativo + lista para troca rapida.
    /// Tap abre Menu com lista de downloadedModels. Selecionar carrega o modelo
    /// via ModelManager.loadModel().
    private var modelSwitcherMenu: some View {
        Menu {
            if deps.modelManager.downloadedModels.isEmpty {
                Text("model.status.downloaded")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(deps.modelManager.downloadedModels, id: \.identifier) { model in
                    Button {
                        Task {
                            try? await deps.modelManager.loadModel(model)
                        }
                    } label: {
                        HStack {
                            Text(model.displayName)
                            if deps.modelManager.activeModel?.identifier == model.identifier {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let active = deps.modelManager.activeModel {
                    Image(systemName: "cpu.fill")
                        .font(.caption)
                        .foregroundStyle(ColorPalette.accent)
                    Text(active.displayName)
                        .font(.caption.weight(.medium))
                } else {
                    Image(systemName: "cpu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("settings.defaultModel.empty")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .accessibilityLabel("model.action.activate")
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: hasActiveModel ? "message" : "cpu")
                .font(.system(size: 48))
                .foregroundStyle(ColorPalette.textTertiary)

            Text(hasActiveModel ? "chat.empty.title" : "settings.defaultModel.empty")
                .font(.rodaHeadline)
                .foregroundStyle(ColorPalette.textSecondary)

            Text("chat.empty.subtitle")
                .font(.rodaCaption)
                .foregroundStyle(ColorPalette.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private var hasActiveModel: Bool {
        deps.modelManager.activeModel != nil
    }
}
