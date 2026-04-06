// Sources/RodaAi/Integrations/Intents/InferenceServiceLocator.swift
import Foundation
import RodaAiCore

/// Localizador de servico para acesso ao InferenceProvider de dentro de App Intents.
/// Intents executam em background thread e precisam de um ponto de acesso ao provider.
@MainActor
final class InferenceServiceLocator {
    static let shared = InferenceServiceLocator()
    var currentProvider: any InferenceProvider = MockInferenceProvider()

    private init() {}
}
