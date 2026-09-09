import Foundation
import Grammar
import Parser
import LR_Parsing
import RNGLR_Parser
import CYK_Parser
import Earley_Parser

public enum REPLComparisonAgreement: String, Codable, Sendable {
    case complete
    case acceptanceOnly
    case divergent
    case inconclusive
}

/// One engine's portable result plus the legacy trees retained for terminal display.
public struct REPLParserRun {
    public let parser: REPLParser
    public let contract: ParseContractSnapshot
    public let trees: [ParseTree]
    public let treeFingerprints: [String]
    public let failure: String?
    public let lrTrace: [LRParserTraceEvent]

    public init(
        parser: REPLParser,
        contract: ParseContractSnapshot,
        trees: [ParseTree],
        input: String,
        failure: String? = nil,
        lrTrace: [LRParserTraceEvent] = []
    ) {
        self.parser = parser
        self.contract = contract
        self.trees = trees
        self.treeFingerprints = trees.map { Self.fingerprint($0, source: input) }.sorted()
        self.failure = failure
        self.lrTrace = lrTrace
    }

    private static func fingerprint(_ tree: ParseTree, source: String) -> String {
        func frame(_ value: String) -> String { "\(value.utf8.count):\(value)" }
        switch tree {
        case .empty:
            return "empty"
        case .leaf(let range):
            return "token:\(frame(String(source[range])))"
        case .node(let nonterminal, let children):
            return "node:\(frame(nonterminal.name))[\(children.map { fingerprint($0, source: source) }.joined())]"
        }
    }
}

/// Comparable results for the same grammar and input across parser engines.
public struct REPLParserComparison {
    public let input: String
    public let runs: [REPLParserRun]

    public init(input: String, runs: [REPLParserRun]) {
        self.input = input
        self.runs = runs
    }

    public var agreement: REPLComparisonAgreement {
        guard runs.count > 1 else { return .inconclusive }
        let accepted = runs.map { $0.contract.status != .rejected }
        guard Set(accepted).count == 1 else { return .divergent }
        guard accepted.first == true else { return .complete }
        return Set(runs.map(\.treeFingerprints)).count == 1 ? .complete : .acceptanceOnly
    }

    public func run(for parser: REPLParser) -> REPLParserRun? {
        runs.first { $0.parser == parser }
    }
}

public enum REPLParserExperiment {
    public static func compare(
        grammar: Grammar,
        input: String,
        precedence: LRPrecedenceSpecification? = nil,
        resolutionPolicy: LRStandardConflictPolicy? = nil
    ) -> REPLParserComparison {
        REPLParserComparison(
            input: input,
            runs: REPLParser.allCases.map {
                run(
                    parser: $0, grammar: grammar, input: input,
                    precedence: precedence, resolutionPolicy: resolutionPolicy
                )
            }
        )
    }

    public static func run(
        parser selected: REPLParser,
        grammar: Grammar,
        input: String,
        precedence: LRPrecedenceSpecification? = nil,
        resolutionPolicy: LRStandardConflictPolicy? = nil
    ) -> REPLParserRun {
        do {
            switch selected {
            case .earley:
                let parser = EarleyParser(grammar: grammar)
                let result = try parser.parse(input)
                return try generalizedRun(
                    parser: selected, result: result,
                    trees: result.isSuccessful ? parser.allSyntaxTrees(for: input) : [], input: input
                )
            case .cyk:
                let parser = CYKParser(grammar: grammar)
                let result = try parser.parse(input)
                return try generalizedRun(
                    parser: selected, result: result,
                    trees: result.isSuccessful ? parser.allSyntaxTrees(for: input) : [], input: input
                )
            case .rnglr:
                let parser = RNGLRParser(grammar: grammar)
                let result = try parser.parse(input)
                return try generalizedRun(
                    parser: selected, result: result,
                    trees: result.isSuccessful ? parser.allSyntaxTrees(for: input) : [], input: input
                )
            case .lr0, .slr, .lalr, .lr1:
                guard let algorithm = selected.lrAlgorithm else {
                    return rejectedRun(parser: selected, input: input, message: "Missing LR algorithm.")
                }
                let result = try LRParser(
                    grammar: grammar, algorithm: algorithm, precedence: precedence,
                    resolutionPolicy: resolutionPolicy
                ).parseOutcome(input, recovery: .none, tracing: true)
                let replay = result.trace.map(\.parseContractEvent)
                return REPLParserRun(
                    parser: selected,
                    contract: result.contractSnapshot(
                        engine: selected.engineDescriptor, replay: replay
                    ),
                    trees: result.tree.map { [$0] } ?? [],
                    input: input,
                    lrTrace: result.trace
                )
            }
        } catch {
            return rejectedRun(parser: selected, input: input, message: String(describing: error))
        }
    }

    private static func generalizedRun<Label: ProductionIdentifiedSPPFLabel & Codable>(
        parser: REPLParser,
        result: ParseResult<Label>,
        trees: [ParseTree],
        input: String
    ) throws -> REPLParserRun {
        let forest = try result.sppfGraph?.portableSnapshot()
        let replay = forest.map(forestReplay) ?? [
            ParseReplayEvent(step: 0, kind: result.isSuccessful ? .accept : .reject)
        ]
        let contract = ParseContractSnapshot(
            engine: parser.engineDescriptor,
            status: result.isSuccessful ? .accepted : .rejected,
            forest: forest,
            replay: replay
        )
        return REPLParserRun(
            parser: parser, contract: contract, trees: trees, input: input
        )
    }

    /// A deterministic exploration order over a completed forest. This is result
    /// replay, not a claim about the generalized engine's internal execution order.
    private static func forestReplay(_ forest: ParseForestSnapshot) -> [ParseReplayEvent] {
        var events = [ParseReplayEvent(step: 0, kind: .start, tokenIndex: 0)]
        for node in forest.nodes {
            let kind: ParseReplayEventKind?
            switch node.kind {
            case .token: kind = .consume
            case .packed: kind = .applyProduction
            case .symbol, .intermediate:
                kind = forest.ambiguityNodes.contains(node.id) ? .discoverAmbiguity : nil
            }
            guard let kind else { continue }
            events.append(ParseReplayEvent(
                step: events.count,
                kind: kind,
                tokenIndex: node.leftExtent,
                productionID: node.productionID,
                forestNodeID: node.id
            ))
        }
        events.append(ParseReplayEvent(step: events.count, kind: .accept))
        return events
    }

    private static func rejectedRun(
        parser: REPLParser, input: String, message: String
    ) -> REPLParserRun {
        let diagnostic = ParseDiagnostic(
            reason: .invalidToken, message: message, source: input
        )
        return REPLParserRun(
            parser: parser,
            contract: ParseContractSnapshot(
                engine: parser.engineDescriptor,
                status: .rejected,
                diagnostics: [ParseDiagnosticSnapshot(diagnostic)],
                replay: [
                    .init(step: 0, kind: .start, tokenIndex: 0),
                    .init(step: 1, kind: .reject, diagnosticReason: .invalidToken),
                ]
            ),
            trees: [],
            input: input,
            failure: message
        )
    }
}

public extension REPLParser {
    var engineDescriptor: ParseEngineDescriptor {
        let displayName: String = switch self {
        case .earley: "Earley"
        case .cyk: "CYK"
        case .rnglr: "RNGLR"
        case .lr0: "LR(0)"
        case .slr: "SLR"
        case .lalr: "LALR"
        case .lr1: "Canonical LR(1)"
        }
        return ParseEngineDescriptor(
            identity: rawValue, displayName: displayName, algorithm: rawValue
        )
    }
}
