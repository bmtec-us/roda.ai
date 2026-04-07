// Sources/RodaAiCore/Inference/VisionInferenceProvider.swift
import Foundation
import MLXVLM
import MLXLMCommon
import MLX

// Reusa `MLXModelConfiguration` typealias + `makeConfiguration(for:)` static
// method definidos em MLXInferenceProvider.swift (internal).

/// Actor de inferencia para modelos VLM (Vision Language Models).
/// Ref: concurrency-model.md — actor custom.
/// Ref: Intro.md Secao 3.3 — VisionInferenceService.
/// Erros: InferenceError (ref: error-types.md).
///
/// Fix audit gap #5: agora le e usa os attachments de ChatMessage.
/// Antes: `messages.map { $0.content }.joined()` — ignorava imagens.
/// Agora: converte `[ChatMessage]` em `[Chat.Message]` (MLXLMCommon) com
/// images inline por mensagem via `Attachment.url`, e `UserInput(chat:)`
/// aplica o template VLM correto com placeholders de imagem.
public actor VisionInferenceProvider: InferenceProvider {

    public var isModelLoaded: Bool { modelContainer != nil }
    public var loadedModelIdentifier: String?

    private var modelContainer: ModelContainer?

    public init() {}

    /// Carrega modelo VLM do HF repo ID ou path local.
    /// - Throws: InferenceError.modelNotFound, .modelCorrupted
    public func loadModel(identifier: String) async throws(InferenceError) {
        if modelContainer != nil {
            await unloadModel()
        }

        // Registra Gemma 4 no VLMTypeRegistry (idempotente)
        await Gemma4Registration.register()

        if MLXInferenceProvider.isLocalPath(identifier) {
            let url = identifier.hasPrefix("file://")
                ? URL(string: identifier)!
                : URL(fileURLWithPath: identifier)
            if let ropeDiagnostics = MLXInferenceProvider.ropeDiagnosticsSummary(at: url) {
                RodaLog.inference.info("RoPE diagnostics (vision): \(ropeDiagnostics, privacy: .public)")
            }
        }

        // Reusa a logica de makeConfiguration do MLXInferenceProvider
        let configuration = MLXInferenceProvider.makeConfiguration(for: identifier)
        do {
            let container = try await VLMModelFactory.shared.loadContainer(
                configuration: configuration
            )
            modelContainer = container
            loadedModelIdentifier = identifier
        } catch {
            throw InferenceError.modelNotFound(identifier: identifier)
        }
    }

    /// Gera tokens em streaming para modelos VLM.
    /// Suporta imagens via `attachments` nos `ChatMessages` (campo `url`).
    /// Cada attachment com mimeType `image/*` e injetado na respectiva Chat.Message.
    /// - Throws: InferenceError.modelNotLoaded, .generationFailed, .generationCancelled
    public func generate(messages: [ChatMessage], config: GenerationConfig) -> AsyncThrowingStream<String, any Error> {
        guard let container = modelContainer else {
            return AsyncThrowingStream<String, any Error> { continuation in
                continuation.finish(throwing: InferenceError.modelNotLoaded)
            }
        }

        let maxTokens = config.maxTokens
        let temperature = config.temperature
        let capturedMessages = messages
        let capturedModelIdentifier = loadedModelIdentifier

        return AsyncThrowingStream<String, any Error> { continuation in
            Task {
                do {
                    try await container.perform { context in
                        // Converte ChatMessage -> Chat.Message com imagens por mensagem
                        let chatMessages = capturedMessages.map { msg -> Chat.Message in
                            let role: Chat.Message.Role
                            switch msg.role {
                            case .system: role = .system
                            case .user: role = .user
                            case .assistant: role = .assistant
                            }
                            // Extrai imagens dos attachments desta mensagem especifica
                            let images: [UserInput.Image] = msg.attachments
                                .filter { $0.mimeType.hasPrefix("image/") }
                                .map { .url($0.url) }
                            return Chat.Message(role: role, content: msg.content, images: images)
                        }

                        let userInput = UserInput(chat: chatMessages)
                        let input = try await context.processor.prepare(input: userInput)
                        var tokenCount = 0

                        let isGemma = (capturedModelIdentifier?.lowercased().contains("gemma") == true)
                        var gemmaInsideTag = false
                        var gemmaControlWindow = ""
                        var previousEmittedCharacter: Character?

                        for try await output in try MLXLMCommon.generate(
                            input: input,
                            parameters: .init(temperature: temperature),
                            context: context
                        ) {
                            if Task.isCancelled {
                                continuation.finish(throwing: InferenceError.generationCancelled)
                                return
                            }
                            tokenCount += 1
                            if tokenCount > maxTokens {
                                continuation.finish()
                                return
                            }
                            if let chunk = output.chunk {
                                if isGemma {
                                    gemmaControlWindow.append(chunk)
                                    if gemmaControlWindow.count > 256 {
                                        gemmaControlWindow = String(gemmaControlWindow.suffix(256))
                                    }

                                    if gemmaControlWindow.contains("<end_of_turn>") || gemmaControlWindow.contains("<start_of_turn>") {
                                        continuation.finish()
                                        return
                                    }

                                    var visible = ""
                                    for char in chunk {
                                        if char == "<" {
                                            gemmaInsideTag = true
                                            continue
                                        }
                                        if char == ">" {
                                            gemmaInsideTag = false
                                            continue
                                        }
                                        if !gemmaInsideTag {
                                            visible.append(char)
                                        }
                                    }

                                    if !visible.isEmpty {
                                        let normalized = Self.normalizeGemmaChunkSpacing(
                                            visible,
                                            previousCharacter: previousEmittedCharacter,
                                            isGemma: isGemma
                                        )
                                        if !normalized.isEmpty {
                                            continuation.yield(normalized)
                                            previousEmittedCharacter = normalized.last
                                        }
                                    }
                                } else {
                                    continuation.yield(chunk)
                                    previousEmittedCharacter = chunk.last
                                }
                            }
                        }
                        continuation.finish()
                    }
                } catch {
                    if Task.isCancelled {
                        continuation.finish(throwing: InferenceError.generationCancelled)
                    } else {
                        continuation.finish(throwing: InferenceError.generationFailed(
                            reason: error.localizedDescription
                        ))
                    }
                }
            }
        }
    }

    private static func normalizeGemmaChunkSpacing(
        _ text: String,
        previousCharacter: Character?,
        isGemma: Bool
    ) -> String {
        guard isGemma,
              let previousCharacter,
              let firstCharacter = text.first else {
            return text
        }

        if previousCharacter.isWhitespace || firstCharacter.isWhitespace {
            return text
        }

        if [":", ";", "!", "?", ")", "]", "}"].contains(previousCharacter),
           firstCharacter.isLetter || firstCharacter.isNumber {
            return " " + text
        }

        if previousCharacter == ".", firstCharacter.isUppercase {
            return " " + text
        }

        return text
    }

    /// Descarrega modelo VLM da memoria.
    public func unloadModel() async {
        modelContainer = nil
        loadedModelIdentifier = nil
        MLX.Memory.clearCache()
    }
}
