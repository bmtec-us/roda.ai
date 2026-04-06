// Sources/RodaAiCore/Models/LocalModel.swift
import Foundation

/// Modelo baixado e instalado localmente.
/// Ref: state-machines.md secao 4 — representacao de modelo no dispositivo.
public struct LocalModel: Equatable, Sendable, Identifiable {
    public let identifier: String
    public let displayName: String
    public let sizeOnDisk: Int64

    public var id: String { identifier }

    public init(identifier: String, displayName: String, sizeOnDisk: Int64) {
        self.identifier = identifier
        self.displayName = displayName
        self.sizeOnDisk = sizeOnDisk
    }
}
