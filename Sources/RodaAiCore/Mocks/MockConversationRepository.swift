// Sources/RodaAiCore/Mocks/MockConversationRepository.swift
import Foundation

/// Mock de ConversationRepository para testes que nao querem inicializar SwiftData.
/// Ref: mock-strategy.md — MockConversationRepository.
///
/// Note: a maioria dos testes deve usar um SwiftData in-memory container ao inves
/// deste mock, pois e mais confiavel. Este mock e util para testar fluxos de erro
/// e contagens de chamadas sem o overhead do ModelContainer.
@MainActor
public final class MockConversationRepository {

    // Storage in-memory
    public private(set) var conversations: [ConversationSummary] = []
    public private(set) var messagesByConversation: [UUID: [MessageSummary]] = [:]

    // Erro injetavel
    public var shouldThrow: PersistenceError?

    // Rastreamento de chamadas (call counts)
    public private(set) var createCallCount = 0
    public private(set) var fetchCallCount = 0
    public private(set) var updateCallCount = 0
    public private(set) var deleteCallCount = 0
    public private(set) var saveCallCount = 0
    public private(set) var addMessageCallCount = 0
    public private(set) var fetchMessagesCallCount = 0
    public private(set) var generateAutoTitleCallCount = 0

    public init() {}

    // MARK: - Create

    public func create(
        title: String,
        modelIdentifier: String
    ) throws(PersistenceError) -> ConversationSummary {
        createCallCount += 1
        if let error = shouldThrow { throw error }

        let summary = ConversationSummary(
            id: UUID(),
            title: title,
            modelIdentifier: modelIdentifier,
            createdAt: Date(),
            updatedAt: Date(),
            messageCount: 0
        )
        conversations.append(summary)
        messagesByConversation[summary.id] = []
        return summary
    }

    // MARK: - Fetch

    public func fetch(matching query: String?) throws(PersistenceError) -> [ConversationSummary] {
        fetchCallCount += 1
        if let error = shouldThrow { throw error }

        let sorted = conversations.sorted { $0.updatedAt > $1.updatedAt }
        guard let query, !query.isEmpty else { return sorted }
        return sorted.filter { $0.title.localizedStandardContains(query) }
    }

    // MARK: - Delete

    public func delete(id: UUID) throws(PersistenceError) {
        deleteCallCount += 1
        if let error = shouldThrow { throw error }

        guard conversations.contains(where: { $0.id == id }) else {
            throw PersistenceError.conversationNotFound(id: id)
        }
        conversations.removeAll { $0.id == id }
        messagesByConversation.removeValue(forKey: id)
    }

    // MARK: - Messages

    public func addMessage(
        to conversationId: UUID,
        role: MessageRole,
        content: String,
        modelIdentifier: String?
    ) throws(PersistenceError) {
        addMessageCallCount += 1
        if let error = shouldThrow { throw error }

        guard conversations.contains(where: { $0.id == conversationId }) else {
            throw PersistenceError.conversationNotFound(id: conversationId)
        }

        let message = MessageSummary(
            id: UUID(),
            role: role,
            content: content,
            modelIdentifier: modelIdentifier,
            timestamp: Date()
        )
        messagesByConversation[conversationId, default: []].append(message)

        // Atualiza updatedAt da conversa
        if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
            let old = conversations[index]
            conversations[index] = ConversationSummary(
                id: old.id,
                title: old.title,
                modelIdentifier: old.modelIdentifier,
                createdAt: old.createdAt,
                updatedAt: Date(),
                messageCount: messagesByConversation[conversationId]?.count ?? 0
            )
        }
    }

    public func fetchMessages(for conversationId: UUID) throws(PersistenceError) -> [MessageSummary] {
        fetchMessagesCallCount += 1
        if let error = shouldThrow { throw error }
        return messagesByConversation[conversationId] ?? []
    }

    public func generateAutoTitle(for conversationId: UUID) throws(PersistenceError) -> String {
        generateAutoTitleCallCount += 1
        if let error = shouldThrow { throw error }

        guard let messages = messagesByConversation[conversationId],
              let firstUserMessage = messages.first(where: { $0.role == .user }) else {
            return "Nova Conversa"
        }

        // Pega primeiras 50 chars da primeira mensagem do usuario
        let title = String(firstUserMessage.content.prefix(50))
        if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
            let old = conversations[index]
            conversations[index] = ConversationSummary(
                id: old.id,
                title: title,
                modelIdentifier: old.modelIdentifier,
                createdAt: old.createdAt,
                updatedAt: old.updatedAt,
                messageCount: old.messageCount
            )
        }
        return title
    }

    public func save() throws(PersistenceError) {
        saveCallCount += 1
        if let error = shouldThrow { throw error }
    }

    // MARK: - Test Helpers

    public func reset() {
        conversations.removeAll()
        messagesByConversation.removeAll()
        createCallCount = 0
        fetchCallCount = 0
        updateCallCount = 0
        deleteCallCount = 0
        saveCallCount = 0
        addMessageCallCount = 0
        fetchMessagesCallCount = 0
        generateAutoTitleCallCount = 0
        shouldThrow = nil
    }
}
