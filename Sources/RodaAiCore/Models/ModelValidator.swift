// Sources/RodaAiCore/Models/ModelValidator.swift
import Foundation
import CryptoKit

public struct ValidationResult: Sendable {
    public let isValid: Bool
    public let sizeOnDisk: Int64
    public let files: [String]
}

public struct ModelValidator: Sendable {
    public init() {}

    /// Validacao sincrona rapida — apenas verifica presenca dos arquivos minimos.
    /// Usado em `ModelManager.scanDownloadedModels` no launch do app para filtrar
    /// downloads parciais sem o custo do I/O assincrono ou SHA256.
    ///
    /// Retorna `true` se o diretorio tem `config.json` + (`tokenizer.json` OU
    /// `tokenizer_config.json`).
    public func isValidModelDirectoryQuickCheck(at modelDirectory: URL) -> Bool {
        let fm = FileManager.default

        let configURL = modelDirectory.appendingPathComponent("config.json")
        guard fm.fileExists(atPath: configURL.path) else { return false }

        let tokenizerURL = modelDirectory.appendingPathComponent("tokenizer.json")
        let tokenizerConfigURL = modelDirectory.appendingPathComponent("tokenizer_config.json")
        guard fm.fileExists(atPath: tokenizerURL.path)
              || fm.fileExists(atPath: tokenizerConfigURL.path) else { return false }

        // Valida que config.json nao esta vazio nem corrompido
        guard let data = try? Data(contentsOf: configURL),
              !data.isEmpty,
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return false
        }

        return true
    }

    /// Valida diretorio do modelo conforme Fluxo de Download (data-flows.md)
    /// 1. Verifica config.json parseavel
    /// 2. Verifica tokenizer.json presente
    /// 3. Verifica checksums SHA256 (se fornecidos)
    public func validate(
        modelDirectory: URL,
        expectedChecksums: [String: String] = [:]
    ) async throws -> ValidationResult {
        let fm = FileManager.default

        // 1. Verifica config.json
        let configURL = modelDirectory.appendingPathComponent("config.json")
        guard fm.fileExists(atPath: configURL.path) else {
            throw DownloadError.fileWriteFailed(
                path: configURL.path,
                reason: "config.json nao encontrado"
            )
        }
        // Valida que e JSON parseavel
        let configData = try Data(contentsOf: configURL)
        guard (try? JSONSerialization.jsonObject(with: configData)) != nil else {
            throw DownloadError.fileWriteFailed(
                path: configURL.path,
                reason: "config.json invalido — nao e JSON"
            )
        }

        // 2. Verifica tokenizer
        let tokenizerURL = modelDirectory.appendingPathComponent("tokenizer.json")
        let tokenizerConfigURL = modelDirectory.appendingPathComponent("tokenizer_config.json")
        guard fm.fileExists(atPath: tokenizerURL.path)
              || fm.fileExists(atPath: tokenizerConfigURL.path) else {
            throw DownloadError.fileWriteFailed(
                path: tokenizerURL.path,
                reason: "tokenizer.json ou tokenizer_config.json nao encontrado"
            )
        }

        // 3. Verifica checksums
        for (filename, expectedHash) in expectedChecksums {
            let fileURL = modelDirectory.appendingPathComponent(filename)
            let fileData = try Data(contentsOf: fileURL)
            let actualHash = SHA256.hash(data: fileData)
                .map { String(format: "%02x", $0) }
                .joined()
            if actualHash != expectedHash {
                throw DownloadError.checksumMismatch(
                    file: filename, expected: expectedHash, actual: actualHash
                )
            }
        }

        // Calcula tamanho total
        var totalSize: Int64 = 0
        var files: [String] = []
        // FileManager.enumerator nao e async-safe. Coletamos os URLs sincronamente
        // antes do contexto async, depois iteramos.
        let urls: [URL] = {
            guard let enumerator = fm.enumerator(at: modelDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
                return []
            }
            return enumerator.compactMap { $0 as? URL }
        }()
        for fileURL in urls {
            let attrs = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            totalSize += Int64(attrs.fileSize ?? 0)
            files.append(fileURL.lastPathComponent)
        }

        return ValidationResult(isValid: true, sizeOnDisk: totalSize, files: files)
    }
}
