import XCTest
@testable import RodaAiCore

final class TestDataTests: XCTestCase {

    func testMakeMessageDefaultsToUser() {
        let msg = TestData.makeMessage()
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.content, "Mensagem de teste")
    }

    func testMakeMessageCustomRole() {
        let msg = TestData.makeMessage(role: .assistant, content: "Resposta")
        XCTAssertEqual(msg.role, .assistant)
        XCTAssertEqual(msg.content, "Resposta")
    }

    func testMakeCatalogEntry() {
        let entry = TestData.makeCatalogEntry()
        XCTAssertEqual(entry.identifier, "test-model")
        XCTAssertEqual(entry.portugueseRating, .bom)
    }

    func testMakeCatalogEntryCustomValues() {
        let entry = TestData.makeCatalogEntry(
            identifier: "custom",
            portugueseRating: .excelente,
            minimumRAM: 8
        )
        XCTAssertEqual(entry.identifier, "custom")
        XCTAssertEqual(entry.portugueseRating, .excelente)
        XCTAssertEqual(entry.minimumRAM, 8)
    }

    func testMakeGenerationConfig() {
        let config = TestData.makeGenerationConfig()
        XCTAssertEqual(config.temperature, 0.7, accuracy: 0.001)
        XCTAssertEqual(config.maxTokens, 100)
    }

    func testMakeGenerationConfigCustom() {
        let config = TestData.makeGenerationConfig(temperature: 0.3, maxTokens: 512)
        XCTAssertEqual(config.temperature, 0.3, accuracy: 0.001)
        XCTAssertEqual(config.maxTokens, 512)
    }

    // MARK: - makeConversation

    func testMakeConversationDefaults() {
        let conv = TestData.makeConversation()
        XCTAssertEqual(conv.title, "Conversa de teste")
        XCTAssertEqual(conv.modelIdentifier, "test-model")
        XCTAssertEqual(conv.messageCount, 3)
        XCTAssertNotNil(conv.lastMessagePreview)
    }

    func testMakeConversationCustomValues() {
        let conv = TestData.makeConversation(
            title: "Custom title",
            modelIdentifier: "llama-3.2-1b",
            messageCount: 10
        )
        XCTAssertEqual(conv.title, "Custom title")
        XCTAssertEqual(conv.modelIdentifier, "llama-3.2-1b")
        XCTAssertEqual(conv.messageCount, 10)
    }

    func testMakeConversationZeroMessages() {
        let conv = TestData.makeConversation(messageCount: 0)
        XCTAssertEqual(conv.messageCount, 0)
        XCTAssertNil(conv.lastMessagePreview)
    }

    func testMakeConversationGeneratesUniqueIds() {
        let conv1 = TestData.makeConversation()
        let conv2 = TestData.makeConversation()
        XCTAssertNotEqual(conv1.id, conv2.id)
    }
}
