import Foundation

/// Monitora uso de memoria em tempo real durante inferencia.
/// @MainActor para updates @Published (ref: concurrency-model.md).
/// Ref: Intro.md Secao 3.3 — Gerenciamento de Memoria.
@MainActor
public final class MemoryMonitor: ObservableObject {

    @Published public var currentUsageBytes: Int64 = 0
    @Published public var availableBytes: Int64 = 0
    @Published public var totalBytes: Int64 = 0

    /// True se uso de memoria excede 80% do total (ref: DeviceCapability.memoryWarningThreshold).
    public var isMemoryPressureHigh: Bool {
        guard totalBytes > 0 else { return false }
        return currentUsageBytes >= DeviceCapability.memoryWarningThreshold
    }

    /// Percentual de uso de memoria (0-100).
    public var usagePercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(currentUsageBytes) / Double(totalBytes) * 100.0
    }

    public init() {}

    /// Atualiza valores de memoria lendo do sistema.
    public func refresh() async {
        totalBytes = DeviceCapability.totalRAM
        availableBytes = DeviceCapability.availableRAM
        currentUsageBytes = totalBytes - availableBytes
    }
}
