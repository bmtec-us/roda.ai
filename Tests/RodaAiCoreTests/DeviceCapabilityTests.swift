import XCTest
@testable import RodaAiCore

final class DeviceCapabilityTests: XCTestCase {

    func testTotalRAMIsPositive() {
        XCTAssertGreaterThan(DeviceCapability.totalRAM, 0)
    }

    func testAvailableRAMIsPositive() {
        XCTAssertGreaterThan(DeviceCapability.availableRAM, 0)
    }

    func testAvailableRAMIsLessThanOrEqualToTotal() {
        XCTAssertLessThanOrEqual(DeviceCapability.availableRAM, DeviceCapability.totalRAM)
    }

    func testCanLoadModelWithSmallRAMReturnsTrue() {
        // 1GB model should be loadable on any modern Apple Silicon device
        XCTAssertTrue(DeviceCapability.canLoadModel(requiringRAM: 1))
    }

    func testCanLoadModelWithExcessiveRAMReturnsFalse() {
        // 1TB model should not be loadable on any current device
        XCTAssertFalse(DeviceCapability.canLoadModel(requiringRAM: 1024))
    }

    func testCanLoadModelUsesTotalRAMNotAvailableRAM() {
        // Verifica que canLoadModel usa totalRAM (capacidade do device)
        // e nao availableRAM (valor flutuante do momento).
        // Um modelo que cabe na RAM total DEVE ser compativel.
        let totalGB = Int(DeviceCapability.totalRAM / 1_073_741_824)
        if totalGB > 0 {
            XCTAssertTrue(DeviceCapability.canLoadModel(requiringRAM: totalGB))
        }
    }

    func testChipNameIsNotEmpty() {
        XCTAssertFalse(DeviceCapability.chipName.isEmpty)
    }

    func testMemoryWarningThresholdAt80Percent() {
        let threshold = DeviceCapability.memoryWarningThreshold
        let total = DeviceCapability.totalRAM
        let expected = Int64(Double(total) * 0.8)
        XCTAssertEqual(threshold, expected)
    }
}
