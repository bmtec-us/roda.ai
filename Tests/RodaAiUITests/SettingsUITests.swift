// Tests/RodaAiUITests/SettingsUITests.swift
//
// UI tests for settings.
// Requires Xcode UI Testing bundle — skipped when running via swift test.
import XCTest

final class SettingsUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"]?
                .contains("RodaAiUITests") != true,
            "SettingsUITests require Xcode UI Testing bundle (not available via swift test)"
        )
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - Temperature Slider

    func testTemperatureSliderIsAdjustable() {
        let settingsTab = app.tabBars.buttons["Ajustes"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()

        let slider = app.sliders.firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 2), "Temperature slider must be present")
        slider.adjust(toNormalizedSliderPosition: 0.5)
    }

    // MARK: - Voice Toggle

    func testVoiceToggleChangesState() {
        let settingsTab = app.tabBars.buttons["Ajustes"]
        settingsTab.tap()

        let toggle = app.switches.firstMatch
        if toggle.waitForExistence(timeout: 2) {
            let initialValue = toggle.value as? String
            toggle.tap()
            let newValue = toggle.value as? String
            XCTAssertNotEqual(initialValue, newValue, "Toggle must change state when tapped")
        }
    }

    // MARK: - Appearance Picker

    func testAppearancePickerShowsThreeOptions() {
        let settingsTab = app.tabBars.buttons["Ajustes"]
        settingsTab.tap()

        // Look for appearance segmented control
        let systemOption = app.buttons["Sistema"]
        let lightOption = app.buttons["Claro"]
        let darkOption = app.buttons["Escuro"]

        if systemOption.waitForExistence(timeout: 2) {
            XCTAssertTrue(systemOption.exists)
            XCTAssertTrue(lightOption.exists)
            XCTAssertTrue(darkOption.exists)
        }
    }

    // MARK: - System Prompt Navigation

    func testTappingSystemPromptOpensPersonalization() {
        let settingsTab = app.tabBars.buttons["Ajustes"]
        settingsTab.tap()

        let systemPromptCell = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'prompt' OR label CONTAINS 'Personalizar'")).firstMatch
        if systemPromptCell.waitForExistence(timeout: 2) {
            systemPromptCell.tap()
            // Personalization view should appear
            let backButton = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(backButton.waitForExistence(timeout: 2))
        }
    }
}
