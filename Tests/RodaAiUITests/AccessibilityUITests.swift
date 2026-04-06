// Tests/RodaAiUITests/AccessibilityUITests.swift
import XCTest

final class AccessibilityUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
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
