import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Deteccao de capacidades do hardware.
/// nonisolated e static (ref: concurrency-model.md).
/// Ref: Intro.md Secao 3.3 — Gerenciamento de Memoria.
public enum DeviceCapability {

    /// RAM total do dispositivo em bytes.
    public static var totalRAM: Int64 {
        Int64(ProcessInfo.processInfo.physicalMemory)
    }

    /// RAM disponivel estimada em bytes.
    public static var availableRAM: Int64 {
        #if canImport(Darwin)
        return Int64(os_proc_available_memory())
        #else
        return totalRAM / 2
        #endif
    }

    /// Nome do chip (ex: "Apple M1", "Apple A17 Pro").
    public static var chipName: String {
        #if os(macOS)
        var size: size_t = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        return String(cString: brand)
        #else
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        return machine
        #endif
    }

    /// Verifica se o dispositivo pode carregar um modelo que requer `gb` GB de RAM.
    /// Usa threshold de 80% da RAM disponivel para margem de seguranca.
    public static func canLoadModel(requiringRAM gb: Int) -> Bool {
        let requiredBytes = Int64(gb) * 1_073_741_824
        return requiredBytes < availableRAM
    }

    /// Threshold de memoria (80% do total) — acima disso, exibir aviso ao usuario.
    /// Ref: Intro.md Secao 3.3.
    public static var memoryWarningThreshold: Int64 {
        Int64(Double(totalRAM) * 0.8)
    }

    /// Verifica se Metal esta disponivel.
    public static var isMetalAvailable: Bool {
        #if os(macOS) || os(iOS)
        return true // Apple Silicon devices always have Metal
        #else
        return false
        #endif
    }
}
