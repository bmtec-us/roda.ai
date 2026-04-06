import XCTest
@testable import RodaAiCore

final class ModelCatalogTests: XCTestCase {

    func testCatalogEntryIsSendable() {
        let entry = CatalogEntry(
            identifier: "gemma-4-e2b",
            displayName: "Gemma 4 E2B",
            provider: "Google",
            familyName: "Gemma",
            parameterCount: "E2B",
            quantization: "Q4_K_M",
            downloadSizeBytes: 2_100_000_000,
            estimatedRAMBytes: 2_800_000_000,
            portugueseRating: .excelente,
            cpuUsageLevel: .medio,
            minimumRAM: 4,
            isVisionCapable: true,
            isReasoningCapable: true,
            huggingFaceRepoId: "bartowski/google_gemma-4-E2B-it-GGUF",
            modelBackend: .gguf,
            downloadFileName: "google_gemma-4-E2B-it-Q4_K_M.gguf"
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
            "parameterCount": "E2B",
            "quantization": "Q4_K_M",
            "downloadSizeBytes": 2100000000,
            "estimatedRAMBytes": 2800000000,
            "portugueseRating": "excelente",
            "cpuUsageLevel": "medio",
            "minimumRAM": 4,
            "isVisionCapable": true,
            "isReasoningCapable": true,
            "huggingFaceRepoId": "bartowski/google_gemma-4-E2B-it-GGUF",
            "modelBackend": "gguf",
            "downloadFileName": "google_gemma-4-E2B-it-Q4_K_M.gguf"
        }
        """.data(using: .utf8)!

        let entry = try JSONDecoder().decode(CatalogEntry.self, from: json)
        XCTAssertEqual(entry.identifier, "gemma-4-e2b")
        XCTAssertEqual(entry.portugueseRating, .excelente)
        XCTAssertTrue(entry.isVisionCapable)
        XCTAssertEqual(entry.backend, .gguf)
        XCTAssertEqual(entry.specificDownloadFile, "google_gemma-4-E2B-it-Q4_K_M.gguf")
    }

    func testCatalogEntryDecodesWithoutBackendDefaultsToMLX() throws {
        let json = """
        {
            "identifier": "llama-3.2-1b",
            "displayName": "Llama 3.2 1B",
            "provider": "Meta",
            "familyName": "Llama",
            "parameterCount": "1B",
            "quantization": "4-bit",
            "downloadSizeBytes": 700000000,
            "estimatedRAMBytes": 900000000,
            "portugueseRating": "bom",
            "cpuUsageLevel": "baixo",
            "minimumRAM": 2,
            "isVisionCapable": false,
            "isReasoningCapable": false,
            "huggingFaceRepoId": "mlx-community/Llama-3.2-1B-Instruct-4bit"
        }
        """.data(using: .utf8)!

        let entry = try JSONDecoder().decode(CatalogEntry.self, from: json)
        XCTAssertEqual(entry.backend, .mlx)
        XCTAssertNil(entry.specificDownloadFile)
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
