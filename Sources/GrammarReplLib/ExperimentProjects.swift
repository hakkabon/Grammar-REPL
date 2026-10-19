import Foundation

/// A deterministic collection of named experiment documents. Projects retain
/// each complete document so entries remain independently portable and replayable.
public struct REPLExperimentProject: Codable {
    public static let currentSchemaVersion = 1
    public static let fingerprintAlgorithm = REPLExperimentDocument.fingerprintAlgorithm

    public let schemaVersion: Int
    public let producer: REPLExperimentProducer
    public let name: String
    public let description: String?
    public let experiments: [REPLExperimentProjectEntry]
    public let fingerprintAlgorithm: String
    public let fingerprint: String

    private init(
        producer: REPLExperimentProducer,
        name: String,
        description: String?,
        experiments: [REPLExperimentProjectEntry],
        fingerprint: String
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.producer = producer
        self.name = name
        self.description = description
        self.experiments = experiments
        fingerprintAlgorithm = Self.fingerprintAlgorithm
        self.fingerprint = fingerprint
    }

    public static func create(
        name: String,
        description: String? = nil,
        experiments: [REPLExperimentProjectEntry] = [],
        producerVersion: String = GrammarREPLRelease.version
    ) throws -> Self {
        try assemble(
            producer: .init(name: "Grammar-REPL", version: producerVersion),
            name: name,
            description: description,
            experiments: experiments
        )
    }

    /// Imports existing standalone artifacts without altering their identities.
    public static func importing(
        name: String,
        documents: [(id: String, document: REPLExperimentDocument)],
        description: String? = nil,
        producerVersion: String = GrammarREPLRelease.version
    ) throws -> Self {
        try create(
            name: name,
            description: description,
            experiments: try documents.map {
                try REPLExperimentProjectEntry(id: $0.id, experiment: $0.document)
            },
            producerVersion: producerVersion
        )
    }

    public func adding(
        id: String,
        title: String? = nil,
        tags: [String] = [],
        experiment: REPLExperimentDocument
    ) throws -> Self {
        guard !experiments.contains(where: { $0.id == id.trimmingCharacters(in: .whitespacesAndNewlines) }) else {
            throw REPLExperimentProjectError.duplicateExperimentID(id)
        }
        return try Self.assemble(
            producer: producer,
            name: name,
            description: description,
            experiments: experiments + [try .init(id: id, title: title, tags: tags, experiment: experiment)]
        )
    }

    public func experiment(id: String) -> REPLExperimentProjectEntry? {
        experiments.first { $0.id == id }
    }

    public func json(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == currentSchemaVersion else {
            throw REPLExperimentProjectError.unsupportedSchema(value.schemaVersion)
        }
        guard value.fingerprintAlgorithm == fingerprintAlgorithm else {
            throw REPLExperimentProjectError.unsupportedFingerprintAlgorithm(value.fingerprintAlgorithm)
        }
        try validateMetadata(name: value.name, description: value.description)
        try validateEntries(value.experiments)
        let expected = try fingerprint(
            schemaVersion: value.schemaVersion,
            producer: value.producer,
            name: value.name,
            description: value.description,
            experiments: value.experiments
        )
        guard expected == value.fingerprint else {
            throw REPLExperimentProjectError.fingerprintMismatch
        }
        return value
    }

    public func verify() throws -> REPLExperimentProjectVerification {
        REPLExperimentProjectVerification(
            projectFingerprint: fingerprint,
            experiments: try experiments.map {
                REPLExperimentProjectCheck(
                    id: $0.id,
                    artifactFingerprint: $0.experiment.fingerprint,
                    verification: try $0.experiment.verify()
                )
            }
        )
    }

    private static func assemble(
        producer: REPLExperimentProducer,
        name: String,
        description: String?,
        experiments: [REPLExperimentProjectEntry]
    ) throws -> Self {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDescription = cleanDescription?.isEmpty == true ? nil : cleanDescription
        try validateMetadata(name: cleanName, description: normalizedDescription)
        let canonical = experiments.sorted { $0.id < $1.id }
        try validateEntries(canonical)
        return Self(
            producer: producer,
            name: cleanName,
            description: normalizedDescription,
            experiments: canonical,
            fingerprint: try fingerprint(
                schemaVersion: currentSchemaVersion,
                producer: producer,
                name: cleanName,
                description: normalizedDescription,
                experiments: canonical
            )
        )
    }

    private static func validateMetadata(name: String, description: String?) throws {
        guard !name.isEmpty, name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              description?.isEmpty != true,
              description == description?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw REPLExperimentProjectError.invalidMetadata
        }
    }

    private static func validateEntries(_ entries: [REPLExperimentProjectEntry]) throws {
        guard entries.map(\.id) == entries.sorted(by: { $0.id < $1.id }).map(\.id) else {
            throw REPLExperimentProjectError.nonCanonicalExperimentOrder
        }
        guard Set(entries.map(\.id)).count == entries.count else {
            throw REPLExperimentProjectError.duplicateExperimentID("<multiple>")
        }
        for entry in entries {
            try entry.validate()
            _ = try REPLExperimentDocument.decode(entry.experiment.json(prettyPrinted: false))
        }
    }

    private static func fingerprint(
        schemaVersion: Int,
        producer: REPLExperimentProducer,
        name: String,
        description: String?,
        experiments: [REPLExperimentProjectEntry]
    ) throws -> String {
        let payload = FingerprintPayload(
            schemaVersion: schemaVersion,
            producer: producer,
            name: name,
            description: description,
            experiments: experiments
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(format: "%016llx", hash)
    }

    private struct FingerprintPayload: Codable {
        let schemaVersion: Int
        let producer: REPLExperimentProducer
        let name: String
        let description: String?
        let experiments: [REPLExperimentProjectEntry]
    }
}

public struct REPLExperimentProjectEntry: Codable {
    public let id: String
    public let title: String?
    public let tags: [String]
    public let experiment: REPLExperimentDocument

    public init(
        id: String,
        title: String? = nil,
        tags: [String] = [],
        experiment: REPLExperimentDocument
    ) throws {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = cleanTitle?.isEmpty == true ? nil : cleanTitle
        self.tags = Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .sorted()
        self.experiment = experiment
        try validate()
    }

    fileprivate func validate() throws {
        guard !id.isEmpty, id == id.trimmingCharacters(in: .whitespacesAndNewlines),
              title?.isEmpty != true,
              title == title?.trimmingCharacters(in: .whitespacesAndNewlines),
              tags.allSatisfy({ !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
              tags == Array(Set(tags)).sorted() else {
            throw REPLExperimentProjectError.invalidEntry(id)
        }
    }
}

public struct REPLExperimentProjectVerification: Codable, Equatable {
    public let projectFingerprint: String
    public let experiments: [REPLExperimentProjectCheck]

    public var matches: Bool { experiments.allSatisfy(\.verification.matches) }
}

public struct REPLExperimentProjectCheck: Codable, Equatable {
    public let id: String
    public let artifactFingerprint: String
    public let verification: REPLExperimentVerification
}

public enum REPLExperimentProjectError: Error, CustomStringConvertible {
    case unsupportedSchema(Int)
    case unsupportedFingerprintAlgorithm(String)
    case fingerprintMismatch
    case invalidMetadata
    case invalidEntry(String)
    case duplicateExperimentID(String)
    case nonCanonicalExperimentOrder

    public var description: String {
        switch self {
        case .unsupportedSchema(let version):
            "Unsupported experiment project schema version \(version)."
        case .unsupportedFingerprintAlgorithm(let algorithm):
            "Unsupported experiment project fingerprint algorithm \(algorithm)."
        case .fingerprintMismatch:
            "Experiment project fingerprint does not match its recorded contents."
        case .invalidMetadata:
            "Experiment project name and description must be canonical and non-empty."
        case .invalidEntry(let id):
            "Experiment project entry \(id.debugDescription) is not canonical."
        case .duplicateExperimentID(let id):
            "Experiment project already contains the identifier \(id.debugDescription)."
        case .nonCanonicalExperimentOrder:
            "Experiment project entries must be ordered by identifier."
        }
    }
}

/// Discriminates the standalone and project formats without weakening either
/// format's fail-closed decoder.
public enum REPLExperimentArtifact {
    case document(REPLExperimentDocument)
    case project(REPLExperimentProject)

    public static func decode(_ data: Data) throws -> Self {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw REPLExperimentProjectError.invalidMetadata
        }
        if object["experiments"] != nil {
            return .project(try REPLExperimentProject.decode(data))
        }
        return .document(try REPLExperimentDocument.decode(data))
    }
}
