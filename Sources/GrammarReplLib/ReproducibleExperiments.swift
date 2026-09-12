import Foundation
import Grammar
import Parser
import LR_Parsing

public enum GrammarREPLRelease {
    public static let version = "0.5.0"
}

/// A self-contained, path- and time-independent record of an engine comparison.
/// The grammar and parser settings are inputs; normalized contracts and tree
/// fingerprints are the expected observations.
public struct REPLExperimentDocument: Codable {
    public static let currentSchemaVersion = 1
    public static let fingerprintAlgorithm = "fnv1a64"

    public let schemaVersion: Int
    public let producer: REPLExperimentProducer
    public let grammar: Grammar
    public let input: String
    public let engines: [REPLParser]
    public let precedence: REPLExperimentPrecedence
    public let resolutionPolicy: String?
    public let agreement: REPLComparisonAgreement
    public let observations: [REPLExperimentObservation]
    public let fingerprintAlgorithm: String
    public let fingerprint: String

    private init(
        producer: REPLExperimentProducer,
        grammar: Grammar,
        input: String,
        engines: [REPLParser],
        precedence: REPLExperimentPrecedence,
        resolutionPolicy: String?,
        agreement: REPLComparisonAgreement,
        observations: [REPLExperimentObservation],
        fingerprint: String
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.producer = producer
        self.grammar = grammar
        self.input = input
        self.engines = engines
        self.precedence = precedence
        self.resolutionPolicy = resolutionPolicy
        self.agreement = agreement
        self.observations = observations
        fingerprintAlgorithm = Self.fingerprintAlgorithm
        self.fingerprint = fingerprint
    }

    public static func capture(
        grammar: Grammar,
        comparison: REPLParserComparison,
        precedence: LRPrecedenceSpecification? = nil,
        resolutionPolicy: LRStandardConflictPolicy? = nil,
        producerVersion: String = GrammarREPLRelease.version
    ) throws -> Self {
        let engines = comparison.runs.map(\.parser)
        guard engines == canonical(engines), Set(engines).count == engines.count else {
            throw REPLExperimentError.invalidEngineOrder
        }
        let settings = REPLExperimentPrecedence(precedence)
        let observations = comparison.runs.map(REPLExperimentObservation.init)
        let producer = REPLExperimentProducer(name: "Grammar-REPL", version: producerVersion)
        let policy = resolutionPolicy?.rawValue
        let material = try fingerprintMaterial(
            producer: producer, grammar: grammar, input: comparison.input,
            engines: engines, precedence: settings, resolutionPolicy: policy,
            agreement: comparison.agreement, observations: observations
        )
        return Self(
            producer: producer, grammar: grammar, input: comparison.input,
            engines: engines, precedence: settings, resolutionPolicy: policy,
            agreement: comparison.agreement, observations: observations,
            fingerprint: stableFingerprint(material)
        )
    }

    public func json(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == currentSchemaVersion else {
            throw REPLExperimentError.unsupportedSchema(value.schemaVersion)
        }
        guard value.fingerprintAlgorithm == fingerprintAlgorithm else {
            throw REPLExperimentError.unsupportedFingerprintAlgorithm(value.fingerprintAlgorithm)
        }
        guard value.engines == canonical(value.engines),
              Set(value.engines).count == value.engines.count,
              value.observations.map(\.parser) == value.engines else {
            throw REPLExperimentError.invalidEngineOrder
        }
        let material = try fingerprintMaterial(
            producer: value.producer, grammar: value.grammar, input: value.input,
            engines: value.engines, precedence: value.precedence,
            resolutionPolicy: value.resolutionPolicy, agreement: value.agreement,
            observations: value.observations
        )
        guard stableFingerprint(material) == value.fingerprint else {
            throw REPLExperimentError.fingerprintMismatch
        }
        _ = try value.precedence.specification(for: value.grammar)
        guard value.resolutionPolicy.flatMap(LRStandardConflictPolicy.init(rawValue:)) != nil
                || value.resolutionPolicy == nil else {
            throw REPLExperimentError.invalidResolutionPolicy(value.resolutionPolicy!)
        }
        return value
    }

    public func verify() throws -> REPLExperimentVerification {
        let precedence = try precedence.specification(for: grammar)
        let policy = resolutionPolicy.flatMap(LRStandardConflictPolicy.init(rawValue:))
        let actual = engines.map {
            REPLParserExperiment.run(
                parser: $0, grammar: grammar, input: input,
                precedence: precedence, resolutionPolicy: policy
            )
        }
        let checks = zip(observations, actual).map(REPLExperimentCheck.init)
        let actualComparison = REPLParserComparison(input: input, runs: actual)
        return REPLExperimentVerification(
            artifactFingerprint: fingerprint,
            expectedAgreement: agreement,
            actualAgreement: actualComparison.agreement,
            engines: checks
        )
    }

    private static func canonical(_ engines: [REPLParser]) -> [REPLParser] {
        REPLParser.allCases.filter(Set(engines).contains)
    }

    private static func fingerprintMaterial(
        producer: REPLExperimentProducer,
        grammar: Grammar,
        input: String,
        engines: [REPLParser],
        precedence: REPLExperimentPrecedence,
        resolutionPolicy: String?,
        agreement: REPLComparisonAgreement,
        observations: [REPLExperimentObservation]
    ) throws -> Data {
        let semanticGrammar = REPLExperimentGrammarIdentity(grammar)
        let payload = REPLExperimentFingerprintPayload(
            schemaVersion: currentSchemaVersion, producer: producer,
            grammar: semanticGrammar, input: input, engines: engines,
            precedence: precedence, resolutionPolicy: resolutionPolicy,
            agreement: agreement, observations: observations
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    private static func stableFingerprint(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(format: "%016llx", hash)
    }
}

public struct REPLExperimentProducer: Codable, Equatable, Sendable {
    public let name: String
    public let version: String
}

public struct REPLExperimentObservation: Codable, Equatable, Sendable {
    public let parser: REPLParser
    public let availability: REPLParserAvailability
    public let unsupportedReason: String?
    public let contract: ParseContractSnapshot
    public let treeFingerprints: [String]

    init(_ run: REPLParserRun) {
        parser = run.parser
        availability = run.availability
        unsupportedReason = run.unsupportedReason
        contract = run.contract
        treeFingerprints = run.treeFingerprints
    }
}

public struct REPLExperimentPrecedence: Codable, Equatable {
    public let levels: [Level]
    public let productionOverrides: [ProductionOverride]

    public struct Level: Codable, Equatable {
        public let level: Int
        public let associativity: String
        public let terminals: [Terminal]
    }

    public struct ProductionOverride: Codable, Equatable {
        public let productionID: String
        public let terminal: Terminal
    }

    init(_ specification: LRPrecedenceSpecification?) {
        levels = (specification?.levels ?? []).map {
            Level(
                level: $0.precedence.level,
                associativity: $0.precedence.associativity.rawValue,
                terminals: $0.terminals.sorted { $0.description < $1.description }
            )
        }.sorted { $0.level < $1.level }
        productionOverrides = (specification?.productionOverrides ?? [:]).map {
            ProductionOverride(productionID: $0.key.lrArtifactID.rawValue, terminal: $0.value)
        }.sorted { $0.productionID < $1.productionID }
    }

    func specification(for grammar: Grammar) throws -> LRPrecedenceSpecification? {
        guard !levels.isEmpty || !productionOverrides.isEmpty else { return nil }
        var seenLevels = Set<Int>()
        var seenTerminals = Set<Terminal>()
        let restoredLevels = try levels.map { level -> LRPrecedenceLevel in
            guard seenLevels.insert(level.level).inserted,
                  let associativity = LRAssociativity(rawValue: level.associativity) else {
                throw REPLExperimentError.invalidPrecedence
            }
            let terminals = Set(level.terminals)
            guard terminals.count == level.terminals.count,
                  terminals.allSatisfy({ seenTerminals.insert($0).inserted }) else {
                throw REPLExperimentError.invalidPrecedence
            }
            return LRPrecedenceLevel(level.level, associativity: associativity, terminals: terminals)
        }
        var overrides: [Production: Terminal] = [:]
        for override in productionOverrides {
            guard let production = grammar.productions.first(where: {
                $0.lrArtifactID.rawValue == override.productionID
            }), overrides[production] == nil else {
                throw REPLExperimentError.invalidPrecedence
            }
            overrides[production] = override.terminal
        }
        return LRPrecedenceSpecification(levels: restoredLevels, productionOverrides: overrides)
    }
}

public struct REPLExperimentVerification: Codable, Equatable, Sendable {
    public let artifactFingerprint: String
    public let expectedAgreement: REPLComparisonAgreement
    public let actualAgreement: REPLComparisonAgreement
    public let engines: [REPLExperimentCheck]

    public var matches: Bool {
        expectedAgreement == actualAgreement && engines.allSatisfy(\.matches)
    }
}

public struct REPLExperimentCheck: Codable, Equatable, Sendable {
    public let parser: REPLParser
    public let matches: Bool
    public let differences: [REPLExperimentDifference]

    init(expected: REPLExperimentObservation, actual: REPLParserRun) {
        parser = expected.parser
        var values: [REPLExperimentDifference] = []
        if expected.availability != actual.availability { values.append(.availability) }
        if expected.unsupportedReason != actual.unsupportedReason { values.append(.unsupportedReason) }
        if expected.contract != actual.contract { values.append(.contract) }
        if expected.treeFingerprints != actual.treeFingerprints { values.append(.derivations) }
        differences = values
        matches = values.isEmpty
    }
}

public enum REPLExperimentDifference: String, Codable, Equatable, Sendable {
    case availability
    case unsupportedReason
    case contract
    case derivations
}

public enum REPLExperimentError: Error, CustomStringConvertible {
    case unsupportedSchema(Int)
    case unsupportedFingerprintAlgorithm(String)
    case fingerprintMismatch
    case invalidEngineOrder
    case invalidPrecedence
    case invalidResolutionPolicy(String)

    public var description: String {
        switch self {
        case .unsupportedSchema(let version):
            "Unsupported experiment schema version \(version)."
        case .unsupportedFingerprintAlgorithm(let algorithm):
            "Unsupported experiment fingerprint algorithm \(algorithm)."
        case .fingerprintMismatch:
            "Experiment fingerprint does not match its recorded contents."
        case .invalidEngineOrder:
            "Experiment engines and observations must be unique and in canonical order."
        case .invalidPrecedence:
            "Experiment contains an invalid precedence specification."
        case .invalidResolutionPolicy(let policy):
            "Experiment contains unknown resolution policy \(policy)."
        }
    }
}

private struct REPLExperimentFingerprintPayload: Codable {
    let schemaVersion: Int
    let producer: REPLExperimentProducer
    let grammar: REPLExperimentGrammarIdentity
    let input: String
    let engines: [REPLParser]
    let precedence: REPLExperimentPrecedence
    let resolutionPolicy: String?
    let agreement: REPLComparisonAgreement
    let observations: [REPLExperimentObservation]
}

/// Only parser-significant grammar state participates in the fingerprint.
/// Sorting removes Set/Dictionary iteration order from experiment identity.
private struct REPLExperimentGrammarIdentity: Codable {
    let start: String
    let grammarForm: String
    let epsilon: String
    let endofile: String
    let productions: [String]
    let lexicalTokens: [LexicalToken]

    struct LexicalToken: Codable {
        let name: String
        let terminal: Terminal
    }

    init(_ grammar: Grammar) {
        start = grammar.start.name
        grammarForm = grammar.grammarForm.rawValue
        epsilon = grammar.epsilon.rawValue
        endofile = grammar.endofile.rawValue
        productions = grammar.productions.map { $0.lrArtifactID.rawValue }.sorted()
        lexicalTokens = grammar.lexicalTokens.map {
            LexicalToken(name: $0.key, terminal: $0.value)
        }.sorted { $0.name < $1.name }
    }
}
