// Sources/RodaAiCore/Utilities/Logger.swift
//
// Wrapper estruturado sobre `os.Logger` com categorias semanticas.
// Uso:
//   RodaLog.inference.info("Model loaded: \(identifier)")
//   RodaLog.download.error("Failed to resume: \(error.localizedDescription)")
//
// Em Debug: todos os niveis sao emitidos ao Console.app e Xcode.
// Em Release: apenas .error e acima sao persistidos (via os.log config).
//
// Ref: concurrency-model.md — `os.Logger` e Sendable.
import Foundation
import os

/// Namespace para as categorias de log do RodaAi.
///
/// Subsystem: `com.bmtec.rodaai` — filtre no Console.app via este subsystem
/// para ver so logs do app.
public enum RodaLog {
    private static let subsystem = "com.bmtec.rodaai"

    /// Logs relacionados a inferencia MLX: carregamento, geracao, unload.
    public static let inference = Logger(subsystem: subsystem, category: "inference")

    /// Logs relacionados a download de modelos do HuggingFace Hub.
    public static let download = Logger(subsystem: subsystem, category: "download")

    /// Logs relacionados a voz: STT, TTS, pipeline.
    public static let voice = Logger(subsystem: subsystem, category: "voice")

    /// Logs relacionados a persistencia SwiftData.
    public static let persistence = Logger(subsystem: subsystem, category: "persistence")

    /// Logs relacionados a lifecycle de modelos: load, unload, delete, scan.
    public static let model = Logger(subsystem: subsystem, category: "model")

    /// Logs genericos do app (ContentView, wiring, etc.).
    public static let app = Logger(subsystem: subsystem, category: "app")
}
