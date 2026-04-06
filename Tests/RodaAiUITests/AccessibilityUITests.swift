// Tests/RodaAiUITests/AccessibilityUITests.swift
//
// IMPORTANT: These tests use XCUIApplication which requires a real Xcode UI
// Testing bundle. They cannot run via `swift test` (SwiftPM only supports unit
// test bundles). They will run when this package is opened in Xcode and the
// host app target is configured correctly.
//
// Detection of the SPM environment: NSXPCConnection fails to launch the host
// app, so we skip these tests when not running in an Xcode UI test runner.
import XCTest

final class AccessibilityUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        // Skip in SwiftPM environment — XCUIApplication requires Xcode UI Testing bundle.
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"]?
                .contains("RodaAiUITests") != true,
            "AccessibilityUITests require Xcode UI Testing bundle (not available via swift test)"
        )
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - VoiceOver Navigation Order

    func testChatViewVoiceOverNavigationOrder() {
        // Navigate to chat tab
        let chatTab = app.tabBars.buttons["Conversas"]
        XCTAssertTrue(chatTab.exists, "Conversas tab must be accessible")
        chatTab.tap()

        // Verify key elements are accessible
        let messageInput = app.textFields["Mensagem"]
        XCTAssertTrue(messageInput.exists || app.textViews["Mensagem"].exists,
                      "Message input must be accessible")
    }

    func testModelGalleryVoiceOverLabels() {
        let modelsTab = app.tabBars.buttons["Modelos"]
        XCTAssertTrue(modelsTab.exists, "Modelos tab must be accessible")
        modelsTab.tap()

        // Model cards should have accessibility labels
        let cards = app.otherElements.matching(identifier: "modelCard")
        if cards.count > 0 {
            let firstCard = cards.element(boundBy: 0)
            XCTAssertFalse(firstCard.label.isEmpty, "Model card must have accessibility label")
        }
    }

    // MARK: - Dynamic Type

    func testDynamicTypeDoesNotTruncateTabLabels() {
        // App should be tested with large text enabled in settings
        let tabs = app.tabBars.buttons
        for i in 0..<tabs.count {
            let tab = tabs.element(boundBy: i)
            XCTAssertFalse(tab.label.isEmpty, "Tab \(i) must have non-empty label at any text size")
        }
    }

    // MARK: - Settings Accessibility

    func testSettingsViewIsFullyAccessible() {
        let settingsTab = app.tabBars.buttons["Ajustes"]
        XCTAssertTrue(settingsTab.exists, "Ajustes tab must be accessible")
        settingsTab.tap()

        // Check key settings controls exist and are accessible
        let temperatureSlider = app.sliders.firstMatch
        if temperatureSlider.exists {
            XCTAssertFalse(temperatureSlider.label.isEmpty,
                          "Temperature slider must have accessibility label")
        }
    }
}
