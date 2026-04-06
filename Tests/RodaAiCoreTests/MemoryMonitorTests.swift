import XCTest
@testable import RodaAiCore

final class MemoryMonitorTests: XCTestCase {

    @MainActor
    func testInitialMemoryUsageIsZero() {
        let monitor = MemoryMonitor()
        XCTAssertEqual(monitor.currentUsageBytes, 0)
    }

    @MainActor
    func testRefreshUpdatesMemoryValues() async {
        let monitor = MemoryMonitor()
        await monitor.refresh()
        // After refresh, available should be populated
        XCTAssertGreaterThan(monitor.availableBytes, 0)
        XCTAssertGreaterThan(monitor.totalBytes, 0)
    }

    @MainActor
    func testIsMemoryPressureHighWhenAboveThreshold() {
        let monitor = MemoryMonitor()
        // Simulate high usage by setting current usage above threshold
        monitor.currentUsageBytes = DeviceCapability.memoryWarningThreshold + 1
        monitor.totalBytes = DeviceCapability.totalRAM
        XCTAssertTrue(monitor.isMemoryPressureHigh)
    }

    @MainActor
    func testIsMemoryPressureLowWhenBelowThreshold() {
        let monitor = MemoryMonitor()
        monitor.currentUsageBytes = 0
        monitor.totalBytes = DeviceCapability.totalRAM
        XCTAssertFalse(monitor.isMemoryPressureHigh)
    }

    @MainActor
    func testUsagePercentageCalculation() {
        let monitor = MemoryMonitor()
        monitor.currentUsageBytes = 4_000_000_000
        monitor.totalBytes = 8_000_000_000
        XCTAssertEqual(monitor.usagePercentage, 50.0, accuracy: 0.1)
    }
}
