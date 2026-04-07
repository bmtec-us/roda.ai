// Sources/RodaAiCore/Settings/UserPreferences.swift
import Foundation
import SwiftData

public enum AppearanceMode: String, Codable, Sendable {
    case system
    case light
    case dark
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

    // MARK: - Voice
    public var voiceEnabled: Bool = true

    // MARK: - Appearance
    public var appearanceMode: AppearanceMode = AppearanceMode.system

    // MARK: - Onboarding
    public var hasCompletedOnboarding: Bool = false

    // MARK: - Computed
    public var clampedTemperature: Float {
        min(max(defaultTemperature, 0.0), 2.0)
    }

    public init() {}
}
