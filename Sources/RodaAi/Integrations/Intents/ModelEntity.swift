// Sources/RodaAi/Integrations/Intents/ModelEntity.swift
import AppIntents

struct ModelEntity: AppEntity {
    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Modelo de IA"
    static var defaultQuery = ModelEntityQuery()
}

struct ModelEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ModelEntity] {
        // Fetch from ModelCatalog
        []
    }

    func suggestedEntities() async throws -> [ModelEntity] {
        // Return downloaded models
        []
    }
}
