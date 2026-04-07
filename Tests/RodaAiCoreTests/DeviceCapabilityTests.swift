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

    func testModelMemoryBudgetIsLessThanTotalRAM() {
        // Budget should be a fraction of total RAM (platform-dependent)
        XCTAssertLessThan(DeviceCapability.modelMemoryBudget, DeviceCapability.totalRAM)
        XCTAssertGreaterThan(DeviceCapability.modelMemoryBudget, 0)
    }

    func testModelMemoryBudgetGBIsConsistentWithBytes() {
        let budgetGB = DeviceCapability.modelMemoryBudgetGB
        let budgetBytes = DeviceCapability.modelMemoryBudget
        // budgetGB should be the floor of budgetBytes / 1GB
        XCTAssertEqual(budgetGB, Int(budgetBytes / 1_073_741_824))
    }

    func testCanLoadModelUsesMemoryBudget() {
        // A model within the memory budget should be loadable
        let budgetGB = DeviceCapability.modelMemoryBudgetGB
        if budgetGB > 0 {
            XCTAssertTrue(DeviceCapability.canLoadModel(requiringRAM: budgetGB))
        }
        // A model exceeding total RAM should NOT be loadable
        let totalGB = DeviceCapability.totalRAMGB
        XCTAssertFalse(DeviceCapability.canLoadModel(requiringRAM: totalGB + 1))
    }

    func testRAMTierIsValid() {
        let tier = DeviceCapability.ramTier
        // On any test machine, tier should be at least .compact
        XCTAssertTrue(RAMTier.allCases.contains(tier))
    }

    func testRAMTierComparable() {
        XCTAssertLessThan(RAMTier.minimal, RAMTier.compact)
        XCTAssertLessThan(RAMTier.compact, RAMTier.standard)
        XCTAssertLessThan(RAMTier.standard, RAMTier.workstation)
        XCTAssertLessThan(RAMTier.workstation, RAMTier.desktop)
    }

    func testTotalRAMGBIsPositive() {
        XCTAssertGreaterThan(DeviceCapability.totalRAMGB, 0)
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
