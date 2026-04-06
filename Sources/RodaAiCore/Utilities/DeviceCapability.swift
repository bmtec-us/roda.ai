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
    /// `os_proc_available_memory()` so esta disponivel em iOS/iPadOS/tvOS/watchOS/visionOS.
    /// No macOS, retorna uma estimativa baseada na memoria total.
    public static var availableRAM: Int64 {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        return Int64(os_proc_available_memory())
        #else
        // macOS nao expoe esta API. Estima 60% da RAM total como disponivel.
        return Int64(Double(totalRAM) * 0.6)
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
    /// Compara contra RAM **total** do dispositivo (nao disponivel no momento),
    /// porque compatibilidade e uma propriedade estatica do hardware — a RAM
    /// disponivel flutua com o uso do sistema e geraria falsos negativos
    /// (ex: iPhone 15 Pro Max com 8GB marcando modelos de 6GB como incompativeis).
    public static func canLoadModel(requiringRAM gb: Int) -> Bool {
        let requiredBytes = Int64(gb) * 1_073_741_824
        return requiredBytes <= totalRAM
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
