import Foundation

/// Catalogo de modelos curados para o RodaAi.
/// Ref: Intro.md Secao 3.2 — Catalogo de Modelos Curado.
public enum ModelCatalog {
    /// Carrega o catalogo do bundle.
    public static func load(from bundle: Bundle = .main) throws -> [CatalogEntry] {
        guard let url = bundle.url(forResource: "ModelCatalog", withExtension: "json") else {
            return []
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([CatalogEntry].self, from: data)
    }
}
