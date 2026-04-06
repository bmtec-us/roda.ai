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
    public var defaultModelIdentifier: String?
    public var systemPrompt: String = ""
    public var defaultTemperature: Float = 0.7
    public var voiceEnabled: Bool = true
    public var appearanceMode: AppearanceMode = .system
    public var hasCompletedOnboarding: Bool = false

    public var clampedTemperature: Float {
        min(max(defaultTemperature, 0.0), 2.0)
    }

    public init() {}
}
