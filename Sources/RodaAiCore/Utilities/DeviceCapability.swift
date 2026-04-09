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

    /// RAM total em GB (arredondado).
    public static var totalRAMGB: Int {
        Int(totalRAM / 1_073_741_824)
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

    /// Orcamento de memoria disponivel para modelos de IA.
    /// Leva em conta os limites da plataforma (jetsam no iOS, overhead no macOS).
    ///
    /// iOS/iPadOS: com entitlement `increased-memory-limit`, apps recebem ~63-75%
    /// do total antes do jetsam matar o processo. Usamos 65% como estimativa
    /// estatica (nao flutua como availableRAM). Sem o entitlement seria ~50%.
    ///
    /// macOS: apps podem usar a maior parte da RAM unificada.
    /// Usamos 75% para deixar espaco para o sistema.
    public static var modelMemoryBudget: Int64 {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        return Int64(Double(totalRAM) * 0.65)
        #else
        return Int64(Double(totalRAM) * 0.75)
        #endif
    }

    /// Orcamento em GB (arredondado para baixo).
    public static var modelMemoryBudgetGB: Int {
        Int(modelMemoryBudget / 1_073_741_824)
    }

    /// Tier de RAM do dispositivo para recomendacoes de modelos.
    public static var ramTier: RAMTier {
        let budget = modelMemoryBudgetGB
        if budget >= 24 { return .desktop }
        if budget >= 10 { return .workstation }
        if budget >= 5 { return .standard }
        if budget >= 3 { return .compact }
        return .minimal
    }

    /// True se o app esta rodando no macOS (vs iOS/iPadOS).
    public static var isMac: Bool {
        #if os(macOS)
        return true
        #else
        return false
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
    /// Compara contra o **orcamento de memoria** (nao RAM total), que leva em
    /// conta limites da plataforma (jetsam no iOS, overhead no macOS).
    ///
    /// Exemplos:
    /// - iPhone 15 Pro Max (8GB total): budget ~4.4GB → modelos ate 4GB
    /// - MacBook Air M4 (16GB total): budget ~12GB → modelos ate 12GB
    /// - Mac Studio M4 Max (64GB total): budget ~48GB → modelos ate 48GB
    public static func canLoadModel(requiringRAM gb: Int) -> Bool {
        compatibilityTier(forModelRAMGB: gb) != .incompatible
    }

    /// Fine-grained tier describing how comfortably a model fits within the
    /// device's memory budget. Used by the Explorer UI to rank models and
    /// show clear visual cues instead of a binary yes/no.
    ///
    /// - `.optimal`:    model RAM ≤ 50% of `modelMemoryBudget` — plenty of headroom
    /// - `.good`:       ≤ 80% — fits with room for the OS and other apps
    /// - `.tight`:      ≤ 100% — borderline, may thrash or crash under pressure
    /// - `.incompatible`: > 100% — guaranteed to fail, download disabled
    public static func compatibilityTier(forModelRAMGB gb: Int) -> CompatibilityTier {
        guard gb > 0 else { return .optimal }
        let requiredBytes = Int64(gb) * 1_073_741_824
        let budget = modelMemoryBudget
        guard budget > 0 else { return .incompatible }
        let ratio = Double(requiredBytes) / Double(budget)
        if ratio <= 0.50 { return .optimal }
        if ratio <= 0.80 { return .good }
        if ratio <= 1.00 { return .tight }
        return .incompatible
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

/// Quão confortavelmente um modelo cabe no orçamento de memória do
/// dispositivo. Usado pela UI (Explorer, ModelCard) para mostrar badges
/// coloridos em vez de um sim/não binário.
public enum CompatibilityTier: String, Codable, Sendable, CaseIterable {
    case optimal       // ≤ 50% do orçamento
    case good          // ≤ 80%
    case tight         // ≤ 100% — instável
    case incompatible  // > 100%

    public var displayName: String {
        switch self {
        case .optimal:      return "Ótimo"
        case .good:         return "Bom"
        case .tight:        return "Apertado"
        case .incompatible: return "Incompatível"
        }
    }

    public var description: String {
        switch self {
        case .optimal:      return "Roda com folga"
        case .good:         return "Roda bem"
        case .tight:        return "Pode forçar a memória"
        case .incompatible: return "Memória insuficiente"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .optimal:      return "checkmark.seal.fill"
        case .good:         return "checkmark.circle.fill"
        case .tight:        return "exclamationmark.triangle.fill"
        case .incompatible: return "lock.fill"
        }
    }

    public var canDownload: Bool {
        self != .incompatible
    }
}

/// Tier de RAM para recomendacoes de modelos na UI.
public enum RAMTier: String, Codable, Sendable, Comparable, CaseIterable {
    /// <3GB budget: apenas modelos 1B (iPhone 12/13 base, iPad mini 6)
    case minimal
    /// 3-4GB budget: modelos ate 3B (iPhone 14, 15 non-Pro, 6GB devices)
    case compact
    /// 5-9GB budget: modelos ate 7B (iPhone 15 Pro+, 16, 8GB Macs)
    case standard
    /// 10-23GB budget: modelos ate 13B (16-32GB Macs)
    case workstation
    /// 24GB+ budget: modelos ate 70B+ (M Pro/Max/Ultra Macs)
    case desktop

    private var sortOrder: Int {
        switch self {
        case .minimal: return 0
        case .compact: return 1
        case .standard: return 2
        case .workstation: return 3
        case .desktop: return 4
        }
    }

    public static func < (lhs: RAMTier, rhs: RAMTier) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}
