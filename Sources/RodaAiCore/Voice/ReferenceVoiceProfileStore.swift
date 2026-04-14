import Foundation

public struct ReferenceVoiceProfile: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var displayName: String
    public var referenceText: String
    public var languageCode: String
    public var audioFileName: String
    public var createdAt: Date

    public var personaId: String { Self.personaPrefix + id }

    public static let personaPrefix = "reference:"

    public init(
        id: String,
        displayName: String,
        referenceText: String,
        languageCode: String,
        audioFileName: String,
        createdAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.referenceText = referenceText
        self.languageCode = languageCode
        self.audioFileName = audioFileName
        self.createdAt = createdAt
    }
}

public enum ReferenceVoiceProfileStore {
    public enum StoreError: Error, LocalizedError {
        case invalidPersonaId
        case profileNotFound

        public var errorDescription: String? {
            switch self {
            case .invalidPersonaId:
                return "Identificador de persona de referência inválido."
            case .profileNotFound:
                return "Perfil de voz de referência não encontrado."
            }
        }
    }

    public static func defaultReferenceText() -> String {
        "Olá, meu nome é Ana e esta é a minha voz de referência. Hoje eu vou ler este texto com ritmo natural, pronúncia brasileira clara e entonação conversacional."
    }

    public static func listProfiles() throws -> [ReferenceVoiceProfile] {
        let dir = try ensureDirectory()
        let files = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let decoder = JSONDecoder()
        var results: [ReferenceVoiceProfile] = []
        for file in files where file.pathExtension.lowercased() == "json" {
            let data = try Data(contentsOf: file)
            let profile = try decoder.decode(ReferenceVoiceProfile.self, from: data)
            results.append(profile)
        }
        return results.sorted { $0.createdAt > $1.createdAt }
    }

    public static func saveProfile(
        displayName: String,
        referenceText: String,
        languageCode: String = "pt-BR",
        sourceAudioURL: URL
    ) throws -> ReferenceVoiceProfile {
        let dir = try ensureDirectory()
        let id = UUID().uuidString.lowercased()
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = normalizedName.isEmpty ? "Voz \(id.prefix(6))" : normalizedName

        let ext = sourceAudioURL.pathExtension.isEmpty ? "wav" : sourceAudioURL.pathExtension.lowercased()
        let audioFileName = "\(id).\(ext)"
        let destinationAudioURL = dir.appendingPathComponent(audioFileName)

        if FileManager.default.fileExists(atPath: destinationAudioURL.path) {
            try FileManager.default.removeItem(at: destinationAudioURL)
        }
        try FileManager.default.copyItem(at: sourceAudioURL, to: destinationAudioURL)

        let profile = ReferenceVoiceProfile(
            id: id,
            displayName: finalName,
            referenceText: referenceText.trimmingCharacters(in: .whitespacesAndNewlines),
            languageCode: languageCode,
            audioFileName: audioFileName,
            createdAt: Date()
        )
        try writeProfile(profile)
        return profile
    }

    public static func deleteProfile(id: String) throws {
        let profile = try loadProfile(id: id)
        let dir = try ensureDirectory()
        let manifestURL = dir.appendingPathComponent("\(profile.id).json")
        let audioURL = dir.appendingPathComponent(profile.audioFileName)

        if FileManager.default.fileExists(atPath: manifestURL.path) {
            try FileManager.default.removeItem(at: manifestURL)
        }
        if FileManager.default.fileExists(atPath: audioURL.path) {
            try FileManager.default.removeItem(at: audioURL)
        }
    }

    public static func profile(forPersonaId personaId: String) throws -> ReferenceVoiceProfile {
        guard let id = profileId(fromPersonaId: personaId) else {
            throw StoreError.invalidPersonaId
        }
        return try loadProfile(id: id)
    }

    public static func audioURL(for profile: ReferenceVoiceProfile) throws -> URL {
        try ensureDirectory().appendingPathComponent(profile.audioFileName)
    }

    public static func profileId(fromPersonaId personaId: String) -> String? {
        guard personaId.hasPrefix(ReferenceVoiceProfile.personaPrefix) else { return nil }
        let value = String(personaId.dropFirst(ReferenceVoiceProfile.personaPrefix.count))
        return value.isEmpty ? nil : value
    }

    private static func writeProfile(_ profile: ReferenceVoiceProfile) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile)
        let url = try ensureDirectory().appendingPathComponent("\(profile.id).json")
        try data.write(to: url, options: .atomic)
    }

    private static func loadProfile(id: String) throws -> ReferenceVoiceProfile {
        let manifestURL = try ensureDirectory().appendingPathComponent("\(id).json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw StoreError.profileNotFound
        }
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode(ReferenceVoiceProfile.self, from: data)
    }

    private static func ensureDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("ReferenceVoiceProfiles", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
