// Sources/RodaAiCore/Data/MessageSummary.swift
import Foundation

/// DTO Sendable para mensagens cruzando fronteira @ModelActor → @MainActor
public struct MessageSummary: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let role: MessageRole
    public let content: String
    public let modelIdentifier: String?
    public let timestamp: Date
    public let attachmentURL: URL?
    public let attachmentMimeType: String?

    public init(
        id: UUID,
        role: MessageRole,
        content: String,
        modelIdentifier: String?,
        timestamp: Date,
        attachmentURL: URL? = nil,
        attachmentMimeType: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.modelIdentifier = modelIdentifier
        self.timestamp = timestamp
        self.attachmentURL = attachmentURL
        self.attachmentMimeType = attachmentMimeType
    }
}
