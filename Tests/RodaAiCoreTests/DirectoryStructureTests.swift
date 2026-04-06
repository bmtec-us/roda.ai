import XCTest
import Foundation

final class DirectoryStructureTests: XCTestCase {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // RodaAiCoreTests/
        .deletingLastPathComponent() // Tests/
        .deletingLastPathComponent() // project root

    func testCoreProtocolsDirectoryExists() {
        let path = projectRoot.appendingPathComponent("Sources/RodaAiCore/Protocols")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: path.path),
            "Sources/RodaAiCore/Protocols/ deve existir"
        )
    }

    func testCoreMocksDirectoryExists() {
        let path = projectRoot.appendingPathComponent("Sources/RodaAiCore/Mocks")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: path.path),
            "Sources/RodaAiCore/Mocks/ deve existir"
        )
    }

    func testCoreInferenceDirectoryExists() {
        let path = projectRoot.appendingPathComponent("Sources/RodaAiCore/Inference")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: path.path),
            "Sources/RodaAiCore/Inference/ deve existir"
        )
    }

    func testCoreDataDirectoryExists() {
        let path = projectRoot.appendingPathComponent("Sources/RodaAiCore/Data")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: path.path),
            "Sources/RodaAiCore/Data/ deve existir"
        )
    }

    func testTestFixturesDirectoryExists() {
        let path = projectRoot.appendingPathComponent("Tests/RodaAiCoreTests/Fixtures")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: path.path),
            "Tests/RodaAiCoreTests/Fixtures/ deve existir"
        )
    }

    func testResourcesDirectoryExists() {
        let path = projectRoot.appendingPathComponent("Resources")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: path.path),
            "Resources/ deve existir"
        )
    }
}
