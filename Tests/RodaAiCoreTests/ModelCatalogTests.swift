import XCTest
@testable import RodaAiCore

final class ModelCatalogTests: XCTestCase {

    func testCatalogEntryIsSendable() {
        let entry = CatalogEntry(
            identifier: "gemma-4-e2b",
            displayName: "Gemma 4 E2B",
            provider: "Google",
            familyName: "Gemma",
            parameterCount: "2B",
            quantization: "4-bit",
            downloadSizeBytes: 1_500_000_000,
            estimatedRAMBytes: 2_000_000_000,
            portugueseRating: .bom,
            cpuUsageLevel: .medio,
            minimumRAM: 4,
            isVisionCapable: false,
            isReasoningCapable: false,
            huggingFaceRepoId: "mlx-community/gemma-4-e2b-it-4bit"
        )
        Task { @MainActor in
            _ = entry.identifier // Sendable check via compilation
        }
        XCTAssertEqual(entry.identifier, "gemma-4-e2b")
    }

    func testCatalogEntryDecodesFromJSON() throws {
        let json = """
        {
            "identifier": "gemma-4-e2b",
            "displayName": "Gemma 4 E2B",
            "provider": "Google",
            "familyName": "Gemma",
            "parameterCount": "2B",
            "quantization": "4-bit",
            "downloadSizeBytes": 1500000000,
            "estimatedRAMBytes": 2000000000,
            "portugueseRating": "bom",
            "cpuUsageLevel": "medio",
            "minimumRAM": 4,
            "isVisionCapable": false,
            "isReasoningCapable": false,
            "huggingFaceRepoId": "mlx-community/gemma-4-e2b-it-4bit"
        }
        """.data(using: .utf8)!

        let entry = try JSONDecoder().decode(CatalogEntry.self, from: json)
        XCTAssertEqual(entry.identifier, "gemma-4-e2b")
        XCTAssertEqual(entry.portugueseRating, .bom)
        XCTAssertFalse(entry.isVisionCapable)
    }

    func testCatalogEntryEncodesToJSON() throws {
        let entry = CatalogEntry(
            identifier: "test",
            displayName: "Test",
            provider: "Test",
            familyName: "Test",
            parameterCount: "1B",
            quantization: "4-bit",
            downloadSizeBytes: 500_000_000,
            estimatedRAMBytes: 700_000_000,
            portugueseRating: .razoavel,
            cpuUsageLevel: .baixo,
            minimumRAM: 2,
            isVisionCapable: false,
            isReasoningCapable: false,
            huggingFaceRepoId: "test/test"
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(CatalogEntry.self, from: data)
        XCTAssertEqual(entry, decoded)
    }

    func testParseValidCatalogFixture() throws {
        let fixtureURL = Bundle.module.url(
            forResource: "valid-catalog",
            withExtension: "json",
            subdirectory: "Fixtures/ModelCatalog"
        )!
        let data = try Data(contentsOf: fixtureURL)
        let entries = try JSONDecoder().decode([CatalogEntry].self, from: data)
        XCTAssertGreaterThanOrEqual(entries.count, 8)
        XCTAssertTrue(entries.contains(where: { $0.identifier == "gemma-4-e2b" }))
    }

    func testParseEmptyCatalogFixture() throws {
        let fixtureURL = Bundle.module.url(
            forResource: "empty-catalog",
            withExtension: "json",
            subdirectory: "Fixtures/ModelCatalog"
        )!
        let data = try Data(contentsOf: fixtureURL)
        let entries = try JSONDecoder().decode([CatalogEntry].self, from: data)
        XCTAssertTrue(entries.isEmpty)
    }

    func testParseMalformedCatalogThrows() throws {
        let fixtureURL = Bundle.module.url(
            forResource: "malformed-catalog",
            withExtension: "json",
            subdirectory: "Fixtures/ModelCatalog"
        )!
        let data = try Data(contentsOf: fixtureURL)
        XCTAssertThrowsError(try JSONDecoder().decode([CatalogEntry].self, from: data))
    }
}
