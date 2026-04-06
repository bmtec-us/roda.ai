// Sources/RodaAiCore/Data/ConversationRepository.swift
import Foundation
import SwiftData

/// Repositorio de conversas usando @ModelActor.
/// Ref: concurrency-model.md secao 4 — "SwiftData nunca sai do @ModelActor"
/// Ref: data-flows.md secao 4 — "Fluxo de Persistencia"
/// Lanca PersistenceError (ref: error-types.md)
@ModelActor
public actor ConversationRepository {

    // MARK: - Create

    /// Cria nova conversa e persiste imediatamente
    /// Ref: data-flows.md — "modelContext.save() EXPLICITO (iOS 18)"
    public func create(
        title: String,
        modelIdentifier: String
    ) throws -> ConversationSummary {
        let conversation = Conversation(
            title: title,
            modelIdentifier: modelIdentifier
        )
        modelContext.insert(conversation)

        do {
            try modelContext.save()
        } catch {
            throw PersistenceError.saveFailed(reason: error.localizedDescription)
        }

        return ConversationSummary(
            id: conversation.id,
            title: conversation.title,
            modelIdentifier: conversation.modelIdentifier,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
            messageCount: 0
        )
    }

    // MARK: - Fetch

    /// Busca conversas com filtro opcional por titulo
    /// Ordena por updatedAt descendente
    /// Ref: intro.md — "Usa fetchCount em FetchDescriptor (nao .count em arrays)"
    public func fetch(matching query: String?) throws -> [ConversationSummary] {
        var descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        if let query, !query.isEmpty {
            descriptor.predicate = #Predicate<Conversation> { conversation in
                conversation.title.localizedStandardContains(query)
            }
        }

        do {
            let conversations = try modelContext.fetch(descriptor)
            return conversations.map { conversation in
                ConversationSummary(
                    id: conversation.id,
                    title: conversation.title,
                    modelIdentifier: conversation.modelIdentifier,
                    createdAt: conversation.createdAt,
                    updatedAt: conversation.updatedAt,
                    lastMessagePreview: conversation.messages.last?.content,
                    messageCount: conversation.messages.count
                )
            }
        } catch {
            throw PersistenceError.fetchFailed(reason: error.localizedDescription)
        }
    }

    /// Retorna contagem sem carregar dataset completo
    public func fetchCount() throws -> Int {
        let descriptor = FetchDescriptor<Conversation>()
        do {
            return try modelContext.fetchCount(descriptor)
        } catch {
            throw PersistenceError.fetchFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Messages

    /// Adiciona mensagem a conversa existente e atualiza updatedAt
    /// Ref: data-flows.md secao 4 — "Adiciona Message ao Conversation, Atualiza conversation.updatedAt"
    public func addMessage(
        to conversationId: UUID,
        role: MessageRole,
        content: String,
        modelIdentifier: String?
    ) throws {
        guard let conversation = try findConversation(by: conversationId) else {
            throw PersistenceError.conversationNotFound(id: conversationId)
        }

        let message = Message(
            role: role,
            content: content,
            modelIdentifier: modelIdentifier
        )
        conversation.messages.append(message)
        conversation.updatedAt = Date()

        do {
            try modelContext.save()
        } catch {
            throw PersistenceError.saveFailed(reason: error.localizedDescription)
        }
    }

    /// Busca mensagens de uma conversa especifica
    public func fetchMessages(for conversationId: UUID) throws -> [MessageSummary] {
        guard let conversation = try findConversation(by: conversationId) else {
            throw PersistenceError.conversationNotFound(id: conversationId)
        }

        return conversation.messages
            .sorted { $0.timestamp < $1.timestamp }
            .map { message in
                MessageSummary(
                    id: message.id,
                    role: message.role,
                    content: message.content,
                    modelIdentifier: message.modelIdentifier,
                    timestamp: message.timestamp
                )
            }
    }

    // MARK: - Delete

    /// Deleta conversa por ID
    /// Lanca PersistenceError.conversationNotFound se nao encontrada
    public func delete(id: UUID) throws {
        guard let conversation = try findConversation(by: id) else {
            throw PersistenceError.conversationNotFound(id: id)
        }

        modelContext.delete(conversation)

        do {
            try modelContext.save()
        } catch {
            throw PersistenceError.deleteFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Auto-Titulo

    /// Gera titulo automatico a partir da primeira mensagem do usuario
    /// Trunca em 50 caracteres com "..."
    public func generateAutoTitle(for conversationId: UUID) throws -> String {
        guard let conversation = try findConversation(by: conversationId) else {
            throw PersistenceError.conversationNotFound(id: conversationId)
        }

        let firstUserMessage = conversation.messages
            .sorted { $0.timestamp < $1.timestamp }
            .first { $0.role == .user }

        guard let content = firstUserMessage?.content, !content.isEmpty else {
            return "Nova conversa"
        }

        if content.count <= 50 {
            return content
        }
        return String(content.prefix(47)) + "..."
    }

    // MARK: - Private

    private func findConversation(by id: UUID) throws -> Conversation? {
        var descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate<Conversation> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
