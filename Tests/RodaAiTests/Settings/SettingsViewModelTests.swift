// Tests/RodaAiTests/Settings/SettingsViewModelTests.swift
import XCTest
import SwiftData
@testable import RodaAi
@testable import RodaAiCore

@MainActor
final class SettingsViewModelTests: XCTestCase {

    private var container: ModelContainer!
    private var viewModel: SettingsViewModel!

    override func setUp() async throws {
        let schema = Schema([UserPreferences.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        viewModel = SettingsViewModel(modelContext: container.mainContext)
    }

    func testLoadDefaultPreferencesWhenNoneSaved() {
        viewModel.loadPreferences()
        XCTAssertEqual(viewModel.temperature, 0.7)
        XCTAssertEqual(viewModel.systemPrompt, "")
        XCTAssertTrue(viewModel.voiceEnabled)
        XCTAssertEqual(viewModel.appearanceMode, .system)
    }

    func testSaveAndReloadPreferences() throws {
        viewModel.temperature = 1.5
        viewModel.systemPrompt = "Voce e um programador."
        viewModel.voiceEnabled = false
        viewModel.appearanceMode = .dark
        try viewModel.savePreferences()

        // Create new ViewModel from same container to verify persistence
        let vm2 = SettingsViewModel(modelContext: container.mainContext)
        vm2.loadPreferences()
        XCTAssertEqual(vm2.temperature, 1.5)
        XCTAssertEqual(vm2.systemPrompt, "Voce e um programador.")
        XCTAssertFalse(vm2.voiceEnabled)
        XCTAssertEqual(vm2.appearanceMode, .dark)
    }

    func testTemperatureSliderClampedRange() {
        viewModel.temperature = 5.0
        XCTAssertEqual(viewModel.clampedTemperature, 2.0)
        viewModel.temperature = -2.0
        XCTAssertEqual(viewModel.clampedTemperature, 0.0)
    }

    func testSystemPromptPresets() {
        let presets = SettingsViewModel.systemPromptPresets
        XCTAssertTrue(presets.keys.contains("general"))
        XCTAssertTrue(presets.keys.contains("programmer"))
        XCTAssertTrue(presets.keys.contains("translator"))
        XCTAssertTrue(presets.keys.contains("summarizer"))
    }
}
