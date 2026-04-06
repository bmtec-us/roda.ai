import XCTest
@testable import RodaAiCore

final class SmokeTests: XCTestCase {
    func testRodaAiCoreModuleImports() {
        // Verifica que o modulo RodaAiCore e importavel
        XCTAssertNotNil(RodaAiCore.self)
    }

    func testRodaAiCoreVersionIsSet() {
        // Verifica que a versao esta definida
        XCTAssertEqual(RodaAiCore.version, "1.0.0")
    }
}
