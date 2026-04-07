// Sources/RodaAiCore/Settings/UserPreferences.swift
import Foundation
import SwiftData
import CoreGraphics

public enum AppearanceMode: String, Codable, Sendable {
    case system
    case light
    case dark
}

public enum ResponseStyle: String, Codable, Sendable, CaseIterable {
    case natural
    case technical
    case detailed
}

public enum ChatFontSizePreference: String, Codable, Sendable, CaseIterable {
    case system
    case smaller
    case larger

    public var scaleFactor: CGFloat {
        switch self {
        case .system: return 1.0
        case .smaller: return 0.9
        case .larger: return 1.12
        }
    }
}

public enum ResponseLengthPreference: String, Codable, Sendable, CaseIterable {
    case compact
    case normal
    case detailed
}

@Model
public final class UserPreferences {
    // MARK: - Model
    public var defaultModelIdentifier: String?

    // MARK: - Generation
    public var systemPrompt: String = ""
    public var defaultTemperature: Float = 0.7
    public var topP: Float = 0.95
    public var maxTokens: Int = 2048
    public var repetitionPenalty: Float = 1.1

    /// Persisted as raw string to avoid enum-cast crashes with older stores.
    public var responseStyleRaw: String = ResponseStyle.natural.rawValue

    /// Persisted as raw string to avoid enum-cast crashes with older stores.
    public var chatFontSizeRaw: String = ChatFontSizePreference.system.rawValue

    /// Persisted as raw string to avoid enum-cast crashes with older stores.
    public var responseLengthRaw: String = ResponseLengthPreference.normal.rawValue

    // MARK: - Voice
    public var voiceEnabled: Bool = true

    // MARK: - Appearance
    public var appearanceMode: AppearanceMode = AppearanceMode.system

    // MARK: - Onboarding
    public var hasCompletedOnboarding: Bool = false

    // MARK: - Computed
    public var responseStyle: ResponseStyle {
        get { ResponseStyle(rawValue: responseStyleRaw) ?? .natural }
        set { responseStyleRaw = newValue.rawValue }
    }

    public var chatFontSize: ChatFontSizePreference {
        get { ChatFontSizePreference(rawValue: chatFontSizeRaw) ?? .system }
        set { chatFontSizeRaw = newValue.rawValue }
    }

    public var responseLength: ResponseLengthPreference {
        get { ResponseLengthPreference(rawValue: responseLengthRaw) ?? .normal }
        set { responseLengthRaw = newValue.rawValue }
    }

    public var clampedTemperature: Float {
        min(max(defaultTemperature, 0.0), 2.0)
    }

    public init() {}
}
