import Foundation

/// Catalogo de modelos curados para o RodaAi.
/// Ref: Intro.md Secao 3.2 — Catalogo de Modelos Curado.
/// Ref: Sources/RodaAiCore/Resources/ModelCatalog.json — source of truth.
public enum ModelCatalog {
    /// Carrega o catalogo do bundle padrao (Bundle.module do target RodaAiCore).
    /// - Throws: `CatalogError.notFound` se o JSON nao estiver no bundle,
    ///           `CatalogError.malformed` se o JSON estiver invalido.
    public static func load() throws -> [CatalogEntry] {
        try load(from: .module)
    }

    /// Carrega o catalogo de um bundle especifico (para injecao em testes).
    public static func load(from bundle: Bundle) throws -> [CatalogEntry] {
        guard let url = bundle.url(forResource: "ModelCatalog", withExtension: "json") else {
            throw CatalogError.notFound
        }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode([CatalogEntry].self, from: data)
        } catch {
            throw CatalogError.malformed(reason: error.localizedDescription)
        }
    }

    /// Tenta carregar o catalogo, retornando array vazio em caso de erro.
    /// Use em SwiftUI previews ou callsites onde falha silenciosa e aceitavel.
    public static func loadSafe() -> [CatalogEntry] {
        (try? load()) ?? []
    }
}

public enum CatalogError: Error, LocalizedError, Equatable {
    case notFound
    case malformed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "Catalogo de modelos nao encontrado no bundle."
        case .malformed(let reason):
            return "Catalogo de modelos mal formatado: \(reason)"
        }
    }
}
