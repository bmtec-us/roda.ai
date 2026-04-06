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
}
