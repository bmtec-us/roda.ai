// Sources/RodaAi/Features/Chat/ChatView.swift
import SwiftUI
import RodaAiCore

struct ChatView: View {
    @State var viewModel: ChatViewModel
    @Environment(AppDependencies.self) private var deps

    var fileProcessor: any FileTextExtractor = FileProcessor()

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if viewModel.messages.isEmpty {
                            emptyStateView
                                .padding(.top, 80)
                        } else {
                            ForEach(Array(viewModel.messages.enumerated()), id: \.offset) { index, message in
                                MessageBubble(message: message)
                                    .id(index)
                            }
                            if case .loading = viewModel.chatState {
                                TypingIndicator()
                                    .id("typingIndicator")
                                    .transition(.blurReplace)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, newCount in
                    withAnimation(.spring(duration: 0.3)) {
                        proxy.scrollTo(newCount - 1, anchor: .bottom)
                    }
                }
            }

            // Error
            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(
                    message: errorMessage,
                    onRetry: { viewModel.resetError() },
                    onDismiss: { viewModel.resetError() }
                )
                .padding(.vertical, 6)
            }

            // Composer
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

    // MARK: - Model Switcher (Glass Capsule)

    private var modelSwitcherMenu: some View {
        Menu {
            if deps.modelManager.downloadedModels.isEmpty {
                Text("model.status.downloaded")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(deps.modelManager.downloadedModels, id: \.identifier) { model in
                    Button {
                        Task { try? await deps.modelManager.loadModel(model) }
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
            modelSwitcherLabel
        }
        .accessibilityLabel("model.action.activate")
    }

    @ViewBuilder
    private var modelSwitcherLabel: some View {
        HStack(spacing: 4) {
            if let active = deps.modelManager.activeModel {
                Image(systemName: "cpu.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
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
        .padding(.vertical, 5)
        .modifier(GlassCapsuleModifier())
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: hasActiveModel ? "message" : "cpu")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
                .symbolEffect(.pulse, options: .repeating.speed(0.5))

            Text(hasActiveModel ? "chat.empty.title" : "settings.defaultModel.empty")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("chat.empty.subtitle")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var hasActiveModel: Bool {
        deps.modelManager.activeModel != nil
    }
}

// MARK: - Glass Capsule Modifier

private struct GlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            content
                .glassEffect(in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
    }
}
