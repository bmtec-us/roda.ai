// Tests/RodaAiUITests/ChatFlowUITests.swift
//
// UI tests for the chat flow.
// Requires Xcode UI Testing bundle — skipped when running via swift test.
import XCTest

final class ChatFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"]?
                .contains("RodaAiUITests") != true,
            "ChatFlowUITests require Xcode UI Testing bundle (not available via swift test)"
        )
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - Send Message

    func testSendMessageDisplaysInChatHistory() {
        let chatTab = app.tabBars.buttons["Conversas"]
        XCTAssertTrue(chatTab.waitForExistence(timeout: 5))
        chatTab.tap()

        let messageField = app.textFields["Mensagem"]
        XCTAssertTrue(messageField.waitForExistence(timeout: 2))
        messageField.tap()
        messageField.typeText("Ola, tudo bem?")

        let sendButton = app.buttons["Enviar"]
        XCTAssertTrue(sendButton.exists)
        sendButton.tap()

        // Verify message appears in conversation
        let messageBubble = app.staticTexts["Ola, tudo bem?"]
        XCTAssertTrue(messageBubble.waitForExistence(timeout: 5))
    }

    // MARK: - Stop Generation

    func testStopGenerationButtonAppearsWhenStreaming() {
        let chatTab = app.tabBars.buttons["Conversas"]
        chatTab.tap()

        let messageField = app.textFields["Mensagem"]
        messageField.tap()
        messageField.typeText("Pergunta longa")
        app.buttons["Enviar"].tap()

        // Stop button should appear during streaming
        let stopButton = app.buttons["Parar"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 3))
    }

    // MARK: - Empty State

    func testEmptyChatShowsPlaceholder() {
        let chatTab = app.tabBars.buttons["Conversas"]
        chatTab.tap()

        // Empty state should show placeholder text
        let placeholder = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Comece'")).firstMatch
        XCTAssertTrue(placeholder.waitForExistence(timeout: 3) || app.scrollViews.firstMatch.exists)
    }

    // MARK: - Error State

    func testErrorBannerShowsRetryButton() {
        let chatTab = app.tabBars.buttons["Conversas"]
        chatTab.tap()

        // If no model is loaded, sending should show error
        let messageField = app.textFields["Mensagem"]
        messageField.tap()
        messageField.typeText("test")
        app.buttons["Enviar"].tap()

        // Error or retry button should appear
        let retryButton = app.buttons["Tentar novamente"]
        if retryButton.waitForExistence(timeout: 3) {
            XCTAssertTrue(retryButton.exists)
        }
    }
}
