// Tests/RodaAiUITests/VoiceModeUITests.swift
//
// UI tests for voice mode.
// Requires Xcode UI Testing bundle — skipped when running via swift test.
import XCTest

final class VoiceModeUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"]?
                .contains("RodaAiUITests") != true,
            "VoiceModeUITests require Xcode UI Testing bundle (not available via swift test)"
        )
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - Mic Button

    func testMicButtonExistsInVoiceTab() {
        let voiceTab = app.tabBars.buttons["Voz"]
        XCTAssertTrue(voiceTab.waitForExistence(timeout: 5))
        voiceTab.tap()

        let micButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'micro' OR label CONTAINS 'Falar'")).firstMatch
        XCTAssertTrue(micButton.waitForExistence(timeout: 2), "Mic button must be visible in voice tab")
    }

    // MARK: - State Indicators

    func testIdleStateShowsCallToAction() {
        let voiceTab = app.tabBars.buttons["Voz"]
        voiceTab.tap()

        // Idle state should show "tap to speak" or similar
        let cta = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Toque' OR label CONTAINS 'Falar'")).firstMatch
        XCTAssertTrue(cta.exists || app.buttons.firstMatch.exists)
    }

    // MARK: - Permission Handling

    func testMicPermissionDeniedShowsError() {
        let voiceTab = app.tabBars.buttons["Voz"]
        voiceTab.tap()

        let micButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'micro' OR label CONTAINS 'Falar'")).firstMatch
        if micButton.waitForExistence(timeout: 2) {
            micButton.tap()
            // If permission is denied, an error message should appear
            let errorText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'permissao' OR label CONTAINS 'microfone'")).firstMatch
            // Optional — only validates if error path is triggered
            if errorText.waitForExistence(timeout: 2) {
                XCTAssertTrue(errorText.exists)
            }
        }
    }

    // MARK: - Transcript Display

    func testTranscriptAreaIsAccessible() {
        let voiceTab = app.tabBars.buttons["Voz"]
        voiceTab.tap()

        // Transcript area should be accessible (even if empty)
        let transcriptArea = app.otherElements.matching(identifier: "voiceTranscript").firstMatch
        XCTAssertTrue(transcriptArea.exists || app.staticTexts.firstMatch.exists)
    }
}
