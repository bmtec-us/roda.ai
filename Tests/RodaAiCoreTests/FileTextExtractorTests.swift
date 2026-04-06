import XCTest
@testable import RodaAiCore

final class FileTextExtractorTests: XCTestCase {

    func testMockExtractsTextFromKnownFile() async throws {
        let mock = MockFileProcessor()
        let url = URL(fileURLWithPath: "/tmp/test.pdf")
        let text = try await mock.extractText(from: url)
        XCTAssertEqual(text, "Conteudo do PDF de teste")
    }

    func testMockReturnsDefaultForUnknownFile() async throws {
        let mock = MockFileProcessor()
        let url = URL(fileURLWithPath: "/tmp/unknown.doc")
        let text = try await mock.extractText(from: url)
        XCTAssertEqual(text, "Conteudo mock")
    }

    func testMockThrowsConfiguredError() async {
        var mock = MockFileProcessor()
        mock.shouldThrow = .unsupportedFormat(extension: "exe")
        let url = URL(fileURLWithPath: "/tmp/test.exe")
        do {
            _ = try await mock.extractText(from: url)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? FileProcessorError, .unsupportedFormat(extension: "exe"))
        }
    }
}
