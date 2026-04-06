import Foundation

public enum MessageRole: String, Codable, Sendable, CaseIterable {
    case user, assistant, system
}

public struct ChatMessage: Sendable, Equatable {
    public let role: MessageRole
    public let content: String
    public let attachments: [Attachment]

    public init(role: MessageRole, content: String, attachments: [Attachment] = []) {
        self.role = role
        self.content = content
        self.attachments = attachments
    }
}

public struct GenerationConfig: Sendable, Equatable {
    public var temperature: Float
    public var topP: Float
    public var maxTokens: Int
    public var repetitionPenalty: Float
    public var seed: UInt64?

    public init(
        temperature: Float = 0.7,
        topP: Float = 0.95,
        maxTokens: Int = 2048,
        repetitionPenalty: Float = 1.1,
        seed: UInt64? = nil
    ) {
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.repetitionPenalty = repetitionPenalty
        self.seed = seed
    }
}

public enum PortugueseRating: String, Codable, Sendable, CaseIterable {
    case excelente, bom, razoavel, limitado
}

public enum CPUUsageLevel: String, Codable, Sendable, CaseIterable {
    case baixo, medio, alto, muitoAlto
}

public enum DarkModePreference: String, Codable, Sendable, CaseIterable {
    case system, light, dark
}

public struct Attachment: Sendable, Equatable {
    public let url: URL
    public let mimeType: String
    public let extractedText: String?

    public init(url: URL, mimeType: String, extractedText: String? = nil) {
        self.url = url
        self.mimeType = mimeType
        self.extractedText = extractedText
    }
}

public struct ModelConfiguration: Sendable, Equatable {
    public let identifier: String
    public let displayName: String
    public let parameterCount: String
    public let quantization: String
    public let estimatedRAM: Int64

    public init(
        identifier: String,
        displayName: String,
        parameterCount: String,
        quantization: String,
        estimatedRAM: Int64
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.parameterCount = parameterCount
        self.quantization = quantization
        self.estimatedRAM = estimatedRAM
    }
}
