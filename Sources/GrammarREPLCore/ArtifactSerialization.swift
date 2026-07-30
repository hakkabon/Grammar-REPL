import Foundation
import Grammar
import LR_Parsing

/// Stable, language-neutral interchange format consumed by workbench and
/// editor clients. New fields may be added within a schema version; breaking
/// representation changes require a new `currentSchemaVersion`.
public struct WorkbenchArtifactEnvelope: Codable, Equatable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let sourceRevision: Int
    public let generatedAt: Date
    public let grammar: SerializedGrammar
    public let analysis: SerializedAnalysis
    public let lr: SerializedLRAutomaton?

    public init(sourceRevision: Int, grammar: Grammar, analysis: GrammarAnalysis, automaton: LRAutomaton? = nil, generatedAt: Date = Date()) {
        schemaVersion = Self.currentSchemaVersion
        self.sourceRevision = sourceRevision
        self.generatedAt = generatedAt
        self.grammar = SerializedGrammar(grammar)
        self.analysis = SerializedAnalysis(analysis)
        lr = automaton.map(SerializedLRAutomaton.init)
    }

    public func json(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(Self.self, from: data)
        guard value.schemaVersion == currentSchemaVersion else {
            throw ArtifactSerializationError.unsupportedSchema(value.schemaVersion)
        }
        return value
    }
}

public enum ArtifactSerializationError: Error, CustomStringConvertible {
    case unsupportedSchema(Int)
    public var description: String {
        switch self { case .unsupportedSchema(let version): "Unsupported workbench artifact schema version \(version)." }
    }
}

public struct SerializedGrammar: Codable, Equatable {
    public let start: String
    public let productions: [SerializedProduction]
    init(_ grammar: Grammar) {
        start = grammar.start.name
        productions = grammar.productions.map { .init(id: $0.lrArtifactID.rawValue, goal: $0.goal.name, description: $0.description) }
            .sorted { $0.id < $1.id }
    }
}

public struct SerializedProduction: Codable, Equatable {
    public let id: String
    public let goal: String
    public let description: String
}

public struct SerializedAnalysis: Codable, Equatable {
    public let first: [SerializedSymbolSet]
    public let follow: [SerializedSymbolSet]
    public let llConflicts: [SerializedLLConflict]

    init(_ analysis: GrammarAnalysis) {
        first = analysis.first.map { .init(symbol: $0.key.description, members: $0.value.map(\.description).sorted()) }.sorted { $0.symbol < $1.symbol }
        follow = analysis.follow.map { .init(symbol: $0.key.name, members: $0.value.map(\.description).sorted()) }.sorted { $0.symbol < $1.symbol }
        llConflicts = analysis.llConflicts.map {
            .init(nonterminal: $0.nonterminal.name, firstProduction: $0.first.lrArtifactID.rawValue, secondProduction: $0.second.lrArtifactID.rawValue, lookaheads: $0.lookaheads.map(\.description).sorted())
        }
    }
}

public struct SerializedSymbolSet: Codable, Equatable {
    public let symbol: String
    public let members: [String]
}

public struct SerializedLLConflict: Codable, Equatable {
    public let nonterminal: String
    public let firstProduction: String
    public let secondProduction: String
    public let lookaheads: [String]
}

public struct SerializedLRAutomaton: Codable, Equatable {
    public let states: [SerializedLRState]
    public let transitions: [SerializedLRTransition]
    public let actions: [SerializedLRTableEntry]
    public let gotos: [SerializedLRTableEntry]
    public let decisions: [SerializedLRDecision]
    public let conflicts: [SerializedLRConflict]

    init(_ automaton: LRAutomaton) {
        states = automaton.states.map { state in
            .init(index: state.id, id: state.identity.rawValue, items: state.items.map { .init(id: $0.identity.rawValue, description: $0.description) }.sorted { $0.id < $1.id })
        }.sorted { $0.index < $1.index }
        transitions = automaton.transitions.map { .init(id: $0.identity.rawValue, source: $0.source, symbol: $0.symbol.description, target: $0.target) }.sorted { $0.id < $1.id }
        actions = automaton.actionTable.flatMap { state, row in row.map { .init(state: state, symbol: $0.key.description, value: Self.action($0.value)) } }
            .sorted { ($0.state, $0.symbol) < ($1.state, $1.symbol) }
        gotos = automaton.gotoTable.flatMap { state, row in row.map { .init(state: state, symbol: $0.key.name, value: String($0.value)) } }
            .sorted { ($0.state, $0.symbol) < ($1.state, $1.symbol) }
        decisions = automaton.actionDecisions.flatMap { _, row in row.values.map(SerializedLRDecision.init) }.sorted { $0.id < $1.id }
        conflicts = automaton.allConflicts.map { conflict in
            .init(id: conflict.identity.rawValue, kind: conflict.kind.rawValue, status: conflict.status.rawValue, state: conflict.state, lookahead: conflict.lookahead.description, witness: conflict.witness.map(\.description), actions: conflict.actions.map(Self.action), candidateIDs: conflict.candidates.map { $0.identity.rawValue }, decisionID: conflict.decision?.identity.rawValue)
        }
    }

    private static func action(_ action: LRAction) -> String {
        switch action {
        case .shift(let state): "shift:\(state)"
        case .reduce(let production): "reduce:\(production.lrArtifactID.rawValue)"
        case .accept: "accept"
        }
    }
}

public struct SerializedLRState: Codable, Equatable { public let index: Int; public let id: String; public let items: [SerializedLRItem] }
public struct SerializedLRItem: Codable, Equatable { public let id: String; public let description: String }
public struct SerializedLRTransition: Codable, Equatable { public let id: String; public let source: Int; public let symbol: String; public let target: Int }
public struct SerializedLRTableEntry: Codable, Equatable { public let state: Int; public let symbol: String; public let value: String }

public struct SerializedLRDecision: Codable, Equatable {
    public let id: String
    public let state: Int
    public let lookahead: String
    public let status: String
    public let selectedAction: String?
    public let resolution: String
    public let candidates: [SerializedLRCandidate]
    init(_ decision: LRActionDecision) {
        id = decision.identity.rawValue
        state = decision.state
        lookahead = decision.lookahead.description
        status = decision.status.rawValue
        selectedAction = decision.selectedAction.map { String(describing: $0) }
        resolution = decision.resolution.description
        candidates = decision.candidates.map { .init(id: $0.identity.rawValue, action: String(describing: $0.action), itemID: $0.item.identity.rawValue, item: $0.item.description, reason: $0.reason.description) }
    }
}

public struct SerializedLRCandidate: Codable, Equatable { public let id: String; public let action: String; public let itemID: String; public let item: String; public let reason: String }
public struct SerializedLRConflict: Codable, Equatable { public let id: String; public let kind: String; public let status: String; public let state: Int; public let lookahead: String; public let witness: [String]; public let actions: [String]; public let candidateIDs: [String]; public let decisionID: String? }
