// Sources/RodaAiCore/Data/Message.swift
import Foundation
import SwiftData

/// SwiftData model para mensagem individual.
/// Ref: data-flows.md secao 4 — armazenada como parte de Conversation
@Model
public final class Message {
    public var id: UUID
    public var role: MessageRole
    public var content: String
    public var modelIdentifier: String?
    public var timestamp: Date

    // Persistencia de anexo principal (imagem)
    public var attachmentURL: String?
    public var attachmentMimeType: String?

    public init(
        role: MessageRole,
        content: String,
        modelIdentifier: String? = nil,
        attachmentURL: String? = nil,
        attachmentMimeType: String? = nil
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.modelIdentifier = modelIdentifier
        self.timestamp = Date()
        self.attachmentURL = attachmentURL
        self.attachmentMimeType = attachmentMimeType
    }
}
