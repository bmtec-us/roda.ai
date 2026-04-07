import Foundation
import MLXLMCommon
import MLXVLM
import Tokenizers

/// Registra o modelo Gemma 4 nos registros VLM do mlx-swift-lm.
/// Chamar `Gemma4Registration.register()` uma vez no launch do app
/// ANTES de qualquer tentativa de carregar um modelo Gemma 4.
///
/// Isso permite usar o Gemma 4 com o VLMModelFactory padrao sem
/// precisar de um fork do mlx-swift-lm.
public enum Gemma4Registration {

    /// Registra o model type "gemma4" e o processor no VLMTypeRegistry.
    /// Seguro para chamar multiplas vezes — idempotente.
    public static func register() async {
        await VLMTypeRegistry.shared.registerModelType("gemma4") {
            (data: Data) throws -> any LanguageModel in
            let config = try JSONDecoder().decode(Gemma4Configuration.self, from: data)
            return Gemma4(config)
        }

        await VLMProcessorTypeRegistry.shared.registerProcessorType("Gemma4Processor") {
            (data: Data, tokenizer: any Tokenizer) throws -> any UserInputProcessor in
            let config = try JSONDecoder().decode(Gemma4ProcessorConfiguration.self, from: data)
            return Gemma4Processor(config, tokenizer: tokenizer)
        }
    }
}
