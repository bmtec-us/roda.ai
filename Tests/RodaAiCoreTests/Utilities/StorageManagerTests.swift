// Tests/RodaAiCoreTests/Utilities/StorageManagerTests.swift
import Testing
import Foundation
@testable import RodaAiCore

@Suite("StorageManager")
struct StorageManagerTests {

    @Test("availableStorage returns positive value")
    func testAvailableStorageIsPositive() throws {
        let storage = StorageManager()
        let available = try storage.availableStorage()
        #expect(available > 0)
    }

    @Test("checkStorage passes when enough space available")
    func testCheckStoragePasses() throws {
        let storage = StorageManager()
        // 1 byte should always be available
        try storage.checkStorage(requiredBytes: 1)
    }

    @Test("checkStorage throws insufficientStorage when not enough space")
    func testCheckStorageThrowsInsufficientStorage() {
        let storage = StorageManager()
        // Request absurdly large amount
        let absurdlyLarge: Int64 = Int64.max
        #expect(throws: DownloadError.self) {
            try storage.checkStorage(requiredBytes: absurdlyLarge)
        }
    }

    @Test("modelDirectorySize calculates size of directory contents")
    func testModelDirectorySize() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )

        // Create a file with known content
        let data = Data(repeating: 0x42, count: 1024)
        try data.write(to: tempDir.appendingPathComponent("test.bin"))

        let storage = StorageManager()
        let size = try storage.modelDirectorySize(at: tempDir)
        #expect(size >= 1024)

        // Cleanup
        try FileManager.default.removeItem(at: tempDir)
    }
}
