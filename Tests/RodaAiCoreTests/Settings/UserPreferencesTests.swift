// Tests/RodaAiCoreTests/Settings/UserPreferencesTests.swift
import XCTest
import SwiftData
@testable import RodaAiCore

final class UserPreferencesTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() async throws {
        let schema = Schema([UserPreferences.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    override func tearDown() async throws {
        container = nil
    }

    // MARK: - Default Values

    func testDefaultPreferencesHaveCorrectDefaults() {
        let prefs = UserPreferences()
        XCTAssertEqual(prefs.defaultTemperature, 0.7)
        XCTAssertNil(prefs.defaultModelIdentifier)
        XCTAssertEqual(prefs.systemPrompt, "")
        XCTAssertTrue(prefs.voiceEnabled)
        XCTAssertEqual(prefs.appearanceMode, .system)
        XCTAssertFalse(prefs.hasCompletedOnboarding)
    }

    // MARK: - Save and Load

    @MainActor
    func testSaveAndLoadPreferences() async throws {
        let context = container.mainContext
        let prefs = UserPreferences()
        prefs.defaultTemperature = 1.2
        prefs.defaultModelIdentifier = "gemma-4-e4b"
        prefs.systemPrompt = "Voce e um assistente prestativo."
        prefs.voiceEnabled = false
        prefs.appearanceMode = .dark
        prefs.hasCompletedOnboarding = true

        context.insert(prefs)
        try context.save()

        let descriptor = FetchDescriptor<UserPreferences>()
        let loaded = try context.fetch(descriptor)
        XCTAssertEqual(loaded.count, 1)
        let p = loaded[0]
        XCTAssertEqual(p.defaultTemperature, 1.2)
        XCTAssertEqual(p.defaultModelIdentifier, "gemma-4-e4b")
        XCTAssertEqual(p.systemPrompt, "Voce e um assistente prestativo.")
        XCTAssertFalse(p.voiceEnabled)
        XCTAssertEqual(p.appearanceMode, .dark)
        XCTAssertTrue(p.hasCompletedOnboarding)
    }

    // MARK: - Temperature Clamping

    func testTemperatureClampedToValidRange() {
        let prefs = UserPreferences()
        prefs.defaultTemperature = 3.0
        XCTAssertEqual(prefs.clampedTemperature, 2.0, "Temperature must clamp to max 2.0")

        prefs.defaultTemperature = -1.0
        XCTAssertEqual(prefs.clampedTemperature, 0.0, "Temperature must clamp to min 0.0")
    }

    // MARK: - Appearance Mode Enum

    func testAppearanceModeRawValues() {
        XCTAssertEqual(AppearanceMode.system.rawValue, "system")
        XCTAssertEqual(AppearanceMode.light.rawValue, "light")
        XCTAssertEqual(AppearanceMode.dark.rawValue, "dark")
    }

    // MARK: - Concurrency Safety

    @MainActor
    func testConcurrentSavesDoNotCorrupt() async throws {
        let context = container.mainContext
        let prefs = UserPreferences()
        context.insert(prefs)
        try context.save()

        // Simulate rapid updates
        for i in 0..<10 {
            prefs.defaultTemperature = Float(i) / 10.0
            try context.save()
        }

        let descriptor = FetchDescriptor<UserPreferences>()
        let loaded = try context.fetch(descriptor)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].defaultTemperature, 0.9, accuracy: 0.01)
    }
}
