// Sources/RodaAiCore/Inference/FoundationModelTools.swift
//
// Foundation Models tool-calling support (iOS 26+, macOS 26+).
//
// Tools let the on-device Apple Intelligence model call into RodaAi code
// mid-response to fetch information or trigger actions. Keeping the tool
// set small (Apple recommends 3-5 max) and safe — only read-only tools
// at this tier, no destructive actions.
//
// Wired in via `FoundationModelInferenceProvider.loadModel(identifier:)`.
// The provider passes `FoundationModelTools.make(...)` into the
// `LanguageModelSession(tools:instructions:)` initializer.
//
// Tools run off the main actor, so anything they touch must be
// `Sendable` or properly isolated. `ModelManager` is `@MainActor`, so
// tools hop to the main actor when reading its state.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)

@available(iOS 26, macOS 26, *)
public enum FoundationModelTools {

    /// Builds the default tool set for a chat session. Tools hold weak-ish
    /// references to the services they need (passed by closure), so the
    /// session can't accidentally extend service lifetimes.
    ///
    /// - Parameters:
    ///   - modelManager: the shared `ModelManager` singleton for read-only
    ///     queries about downloaded and active models.
    ///   - conversationRepository: the shared repository for conversation
    ///     history search.
    public static func make(
        modelManager: ModelManager,
        conversationRepository: ConversationRepository
    ) -> [any Tool] {
        [
            ListDownloadedModelsTool(modelManager: modelManager),
            ActiveModelInfoTool(modelManager: modelManager),
            SearchConversationHistoryTool(repository: conversationRepository)
        ]
    }
}

// MARK: - ListDownloadedModelsTool

@available(iOS 26, macOS 26, *)
public struct ListDownloadedModelsTool: Tool {
    public let name = "listDownloadedModels"
    public let description = """
        Lista os modelos de IA atualmente baixados no dispositivo do usuario.
        Use quando o usuario perguntar quais modelos estao disponiveis, baixados, ou instalados.
        """

    let modelManager: ModelManager

    @Generable
    public struct Arguments: Sendable {}

    public func call(arguments: Arguments) async throws -> String {
        let models = await MainActor.run { modelManager.downloadedModels }
        guard !models.isEmpty else {
            return "Nenhum modelo baixado no dispositivo."
        }
        let lines = models.map { "- \($0.displayName) (\($0.identifier))" }
        return "Modelos baixados:\n" + lines.joined(separator: "\n")
    }
}

// MARK: - ActiveModelInfoTool

@available(iOS 26, macOS 26, *)
public struct ActiveModelInfoTool: Tool {
    public let name = "activeModelInfo"
    public let description = """
        Retorna o modelo de IA que esta atualmente carregado e ativo.
        Use quando o usuario perguntar qual modelo esta sendo usado.
        """

    let modelManager: ModelManager

    @Generable
    public struct Arguments: Sendable {}

    public func call(arguments: Arguments) async throws -> String {
        let active = await MainActor.run { modelManager.activeModel }
        guard let active else {
            return "Nenhum modelo ativo no momento."
        }
        return "Modelo ativo: \(active.displayName) (\(active.identifier))"
    }
}

// MARK: - SearchConversationHistoryTool

@available(iOS 26, macOS 26, *)
public struct SearchConversationHistoryTool: Tool {
    public let name = "searchConversationHistory"
    public let description = """
        Busca nas conversas passadas do usuario por um termo ou assunto.
        Use quando o usuario perguntar sobre algo que ele ou voce disse em conversas anteriores.
        """

    let repository: ConversationRepository

    @Generable
    public struct Arguments: Sendable {
        @Guide(description: "Termo ou assunto para buscar nas conversas passadas")
        public let query: String
    }

    public func call(arguments: Arguments) async throws -> String {
        let trimmed = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Consulta vazia — forneca um termo para buscar."
        }

        let all = try await repository.fetch(matching: nil)
        let ranked = await SemanticSearchService().rank(all, query: trimmed)
        let top = ranked.prefix(5)

        guard !top.isEmpty else {
            return "Nenhuma conversa anterior encontrada sobre \"\(trimmed)\"."
        }

        let lines = top.enumerated().map { idx, convo in
            let preview = convo.lastMessagePreview.map { " — \($0.prefix(80))" } ?? ""
            return "\(idx + 1). \(convo.title)\(preview)"
        }
        return "Conversas relacionadas a \"\(trimmed)\":\n" + lines.joined(separator: "\n")
    }
}

#endif
