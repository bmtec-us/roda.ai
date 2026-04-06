// Sources/RodaAi/Integrations/Intents/ModelEntity.swift
import AppIntents
import RodaAiCore

/// AppEntity que expoe os modelos curados (do ModelCatalog) para Siri/Shortcuts.
/// Antes: retornava `[]` em ambos os queries (audit gap #6).
/// Agora: carrega do catalogo real do bundle e permite ao usuario escolher
/// um modelo via Siri Shortcuts.
struct ModelEntity: AppEntity {
    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Modelo de IA"
    static let defaultQuery = ModelEntityQuery()

    /// Constroi entity a partir de CatalogEntry
    init(from entry: CatalogEntry) {
        self.id = entry.identifier
        self.name = entry.displayName
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

struct ModelEntityQuery: EntityQuery {
    /// Retorna as entities correspondentes a IDs especificos (ja vistos em outros
    /// intents/shortcuts). Carrega do catalogo do bundle.
    func entities(for identifiers: [String]) async throws -> [ModelEntity] {
        let catalog = ModelCatalog.loadSafe()
        return catalog
            .filter { identifiers.contains($0.identifier) }
            .map(ModelEntity.init(from:))
    }

    /// Retorna os modelos sugeridos — o catalogo inteiro ordenado alfabeticamente.
    /// Os primeiros ~5 apareceriam no picker do Shortcuts app.
    func suggestedEntities() async throws -> [ModelEntity] {
        let catalog = ModelCatalog.loadSafe()
        return catalog
            .sorted { $0.displayName < $1.displayName }
            .map(ModelEntity.init(from:))
    }
}
