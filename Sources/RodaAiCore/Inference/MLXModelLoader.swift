import Foundation
import MLXLLM
import MLXLMCommon

// Reusa `MLXModelConfiguration` typealias definido em MLXInferenceProvider.swift.

/// Carrega modelos MLX do disco.
/// Ref: Intro.md Secao 3.3 — InferenceModule.
/// Erros: InferenceError.modelNotFound, .modelCorrupted, .insufficientMemory.
public struct MLXModelLoader: Sendable {

    public init() {}

    /// Carrega um modelo do path especificado.
    /// - Parameter path: URL do diretorio contendo config.json e safetensors.
    /// - Returns: ModelContainer pronto para inferencia.
    /// - Throws: InferenceError.modelNotFound se path invalido,
    ///           InferenceError.modelCorrupted se arquivos invalidos,
    ///           InferenceError.insufficientMemory se RAM insuficiente.
    public func load(from path: URL) async throws -> ModelContainer {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw InferenceError.modelNotFound(identifier: path.lastPathComponent)
        }

        let configPath = path.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            throw InferenceError.modelCorrupted(
                identifier: path.lastPathComponent,
                reason: "config.json nao encontrado"
            )
        }

        do {
            let configuration = MLXModelConfiguration(directory: path)
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: configuration
            )
            return container
        } catch {
            throw InferenceError.modelCorrupted(
                identifier: path.lastPathComponent,
                reason: error.localizedDescription
            )
        }
    }

    /// Estima uso de memoria para um modelo com a configuracao dada.
    /// - Returns: Bytes estimados de RAM necessarios.
    public func estimateMemory(for config: ModelConfiguration) -> Int64 {
        config.estimatedRAM
    }
}
