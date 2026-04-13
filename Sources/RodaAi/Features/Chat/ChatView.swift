// Sources/RodaAi/Features/Chat/ChatView.swift
import SwiftUI
import RodaAiCore

struct ChatView: View {
    @State var viewModel: ChatViewModel
    let chatFontSize: ChatFontSizePreference
    var onResponseLengthChange: (ResponseLengthPreference) -> Void = { _ in }
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
                                MessageBubble(
                                    message: message,
                                    chatFontScale: chatFontSize.scaleFactor,
                                    responseLength: viewModel.responseLength,
                                    loadingText: viewModel.loadingIndicatorText
                                )
                                    .id(index)
                            }
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("chatBottomAnchor")
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, newCount in
                    guard newCount > 0 else { return }
                    withAnimation(.spring(duration: 0.3)) {
                        proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.messages.last?.content ?? "") { _, _ in
                    withAnimation(.linear(duration: 0.15)) {
                        proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
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

            if viewModel.isOptimizingContext || viewModel.contextOptimizationTimedOut || viewModel.contextWarningText != nil {
                contextStatusChip
                    .padding(.bottom, 6)
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
        .background(ColorPalette.surface)
        .navigationTitle("chat.title")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                modelSwitcherMenu
            }
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                responseLengthMenu
            }
            #else
            ToolbarItem(placement: .automatic) {
                responseLengthMenu
            }
            #endif
        }
        .onChange(of: viewModel.responseLength) { _, newValue in
            onResponseLengthChange(newValue)
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
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Image(systemName: "cpu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Modelo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 150)
        // NOTE: No custom .glassShape here — the enclosing ToolbarItem on
        // iOS 26 already provides Liquid Glass automatically. Stacking a
        // second glass layer produces a double-glass seam.
    }

    private var responseLengthMenu: some View {
        Menu {
            ForEach(ResponseLengthPreference.allCases, id: \.rawValue) { option in
                Button {
                    viewModel.responseLength = option
                } label: {
                    HStack {
                        Text(responseLengthTitle(option))
                        if viewModel.responseLength == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(responseLengthTitle(viewModel.responseLength), systemImage: "textformat.size")
                .font(.caption)
        }
        .accessibilityLabel("Comprimento da resposta")
    }

    private func responseLengthTitle(_ option: ResponseLengthPreference) -> String {
        switch option {
        case .compact: return "Curta"
        case .normal: return "Normal"
        case .detailed: return "Detalhada"
        }
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

    private var contextStatusChip: some View {
        HStack(spacing: 8) {
            if viewModel.isOptimizingContext {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: contextStatusIcon)
                    .font(.caption)
                    .foregroundStyle(contextStatusColor)
            }

            Text(viewModel.contextWarningText ?? viewModel.loadingIndicatorText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if viewModel.estimatedPromptTokens > 0 {
                Text("~\(viewModel.estimatedPromptTokens)/\(viewModel.estimatedTokenBudget) tok")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Status info, not an action — plain surface, not glass.
        .background(ColorPalette.surfaceElevated)
        .clipShape(Capsule())
        .padding(.horizontal, 12)
    }

    private var contextStatusIcon: String {
        if viewModel.didTrimInputThisTurn { return "scissors" }
        if viewModel.contextOptimizationTimedOut { return "exclamationmark.triangle" }
        switch viewModel.contextPressureLevel {
        case .normal:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.circle"
        case .critical:
            return "exclamationmark.triangle"
        }
    }

    private var contextStatusColor: Color {
        if viewModel.didTrimInputThisTurn { return .orange }
        switch viewModel.contextPressureLevel {
        case .normal:
            return .secondary
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    private var hasActiveModel: Bool {
        deps.modelManager.activeModel != nil
    }
}

