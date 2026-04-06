// Sources/RodaAiCore/Data/ConversationSummary.swift
import Foundation

/// DTO Sendable para cruzar fronteira @ModelActor → @MainActor
/// Ref: concurrency-model.md — "Retorna DTOs (Sendable) para camada de apresentacao"
public struct ConversationSummary: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let modelIdentifier: String
    public let createdAt: Date
    public let updatedAt: Date
    public let lastMessagePreview: String?
    public let messageCount: Int

    public init(
        id: UUID,
        title: String,
        modelIdentifier: String,
        createdAt: Date,
        updatedAt: Date,
        lastMessagePreview: String? = nil,
        messageCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.modelIdentifier = modelIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastMessagePreview = lastMessagePreview
        self.messageCount = messageCount
    }
}
