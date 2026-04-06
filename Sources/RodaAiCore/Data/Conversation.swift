// Sources/RodaAiCore/Data/Conversation.swift
import Foundation
import SwiftData

/// SwiftData model para conversa.
/// Ref: data-flows.md secao 4 — "Fluxo de Persistencia"
/// Protegido por NSFileProtectionComplete (ref: intro.md)
@Model
public final class Conversation {
    public var id: UUID
    public var title: String
    public var modelIdentifier: String
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade)
    public var messages: [Message]

    public init(
        title: String,
        modelIdentifier: String
    ) {
        self.id = UUID()
        self.title = title
        self.modelIdentifier = modelIdentifier
        self.createdAt = Date()
        self.updatedAt = Date()
        self.messages = []
    }
}
