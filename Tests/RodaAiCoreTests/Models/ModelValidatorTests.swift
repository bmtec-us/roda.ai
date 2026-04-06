// Tests/RodaAiCoreTests/Models/ModelValidatorTests.swift
import Testing
import Foundation
@testable import RodaAiCore

@Suite("ModelValidator")
struct ModelValidatorTests {

    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)

    init() throws {
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
    }

    @Test("validates model directory with all required files")
    func testValidModelDirectory() async throws {
        // Setup: create required files
        try createFile("config.json", content: "{\"model_type\": \"gemma\"}")
        try createFile("tokenizer.json", content: "{\"version\": \"1.0\"}")
        try createFile("model.safetensors", content: "fake-weights")

        let validator = ModelValidator()
        let result = try await validator.validate(modelDirectory: tempDir)
        #expect(result.isValid == true)
        #expect(result.sizeOnDisk > 0)
    }

    @Test("fails when config.json is missing")
    func testMissingConfigJson() async {
        let validator = ModelValidator()
        do {
            _ = try await validator.validate(modelDirectory: tempDir)
            Issue.record("Expected DownloadError to be thrown")
        } catch let error as DownloadError {
            if case .fileWriteFailed(_, let reason) = error {
                #expect(reason.contains("config.json"))
            } else {
                Issue.record("Expected .fileWriteFailed but got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("fails when tokenizer.json is missing")
    func testMissingTokenizerJson() async throws {
        try createFile("config.json", content: "{\"model_type\": \"gemma\"}")
        try createFile("model.safetensors", content: "fake-weights")

        let validator = ModelValidator()
        do {
            _ = try await validator.validate(modelDirectory: tempDir)
            Issue.record("Expected DownloadError to be thrown")
        } catch let error as DownloadError {
            if case .fileWriteFailed(_, let reason) = error {
                #expect(reason.contains("tokenizer"))
            } else {
                Issue.record("Expected .fileWriteFailed but got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("checksum mismatch throws checksumMismatch error")
    func testChecksumMismatch() async throws {
        try createFile("config.json", content: "{\"model_type\": \"gemma\"}")
        try createFile("tokenizer.json", content: "{\"version\": \"1.0\"}")
        try createFile("model.safetensors", content: "fake-weights")

        let validator = ModelValidator()
        do {
            _ = try await validator.validate(
                modelDirectory: tempDir,
                expectedChecksums: ["model.safetensors": "expected-sha256-hash"]
            )
            Issue.record("Expected DownloadError.checksumMismatch")
        } catch let error as DownloadError {
            if case .checksumMismatch(let file, let expected, _) = error {
                #expect(file == "model.safetensors")
                #expect(expected == "expected-sha256-hash")
            } else {
                Issue.record("Expected .checksumMismatch but got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Quick check (sync) — partial download detection

    @Test("quick check passes when config and tokenizer present")
    func testQuickCheckValid() throws {
        try createFile("config.json", content: "{\"model_type\": \"gemma\"}")
        try createFile("tokenizer.json", content: "{\"version\": \"1.0\"}")

        let validator = ModelValidator()
        #expect(validator.isValidModelDirectoryQuickCheck(at: tempDir) == true)
    }

    @Test("quick check accepts tokenizer_config.json as alternative to tokenizer.json")
    func testQuickCheckAcceptsTokenizerConfig() throws {
        try createFile("config.json", content: "{\"model_type\": \"llama\"}")
        try createFile("tokenizer_config.json", content: "{}")

        let validator = ModelValidator()
        #expect(validator.isValidModelDirectoryQuickCheck(at: tempDir) == true)
    }

    @Test("quick check fails when config.json is missing")
    func testQuickCheckMissingConfig() throws {
        try createFile("tokenizer.json", content: "{\"version\": \"1.0\"}")

        let validator = ModelValidator()
        #expect(validator.isValidModelDirectoryQuickCheck(at: tempDir) == false)
    }

    @Test("quick check fails when tokenizer is missing")
    func testQuickCheckMissingTokenizer() throws {
        try createFile("config.json", content: "{\"model_type\": \"gemma\"}")

        let validator = ModelValidator()
        #expect(validator.isValidModelDirectoryQuickCheck(at: tempDir) == false)
    }

    @Test("quick check fails when config.json is empty")
    func testQuickCheckEmptyConfig() throws {
        try createFile("config.json", content: "")
        try createFile("tokenizer.json", content: "{}")

        let validator = ModelValidator()
        #expect(validator.isValidModelDirectoryQuickCheck(at: tempDir) == false)
    }

    @Test("quick check fails when config.json is not JSON")
    func testQuickCheckInvalidJSON() throws {
        try createFile("config.json", content: "not valid json at all")
        try createFile("tokenizer.json", content: "{}")

        let validator = ModelValidator()
        #expect(validator.isValidModelDirectoryQuickCheck(at: tempDir) == false)
    }

    @Test("quick check fails for empty directory")
    func testQuickCheckEmptyDir() {
        let validator = ModelValidator()
        #expect(validator.isValidModelDirectoryQuickCheck(at: tempDir) == false)
    }

    // MARK: - Helpers

    private func createFile(_ name: String, content: String) throws {
        let fileURL = tempDir.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
