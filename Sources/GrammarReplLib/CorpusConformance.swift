import Foundation
import Grammar
import Lexer
import LR_Parsing
import Parser

public struct GrammarREPLCorpusObservation: Codable, Equatable, Sendable {
    public let id: String
    public let status: String
    public let root: String?
    public let diagnostics: Int
    public let recoveryEdits: Int

    public init(id: String, status: String, root: String? = nil, diagnostics: Int, recoveryEdits: Int) {
        self.id = id
        self.status = status
        self.root = root
        self.diagnostics = diagnostics
        self.recoveryEdits = recoveryEdits
    }
}

/// Non-terminal adapter from the shared ecosystem corpus to Grammar-REPL's
/// canonical LR parsing path. Command rendering, history, and line editing are
/// deliberately outside this boundary.
public enum GrammarREPLCorpusConformance {
    public static func evaluate(_ data: Data) throws -> [GrammarREPLCorpusObservation] {
        let corpus = try JSONDecoder().decode(Corpus.self, from: data)
        guard (1...2).contains(corpus.schemaVersion) else {
            throw CorpusConformanceError("unsupported corpus schema version \(corpus.schemaVersion)")
        }

        var grammars: [String: (Grammar, LRPrecedenceSpecification?)] = [:]
        for model in corpus.grammars {
            guard grammars[model.id] == nil else {
                throw CorpusConformanceError("duplicate grammar '\(model.id)'")
            }
            grammars[model.id] = try makeGrammar(model)
        }

        var caseIDs = Set<String>()
        return try corpus.cases.map { testCase in
            guard caseIDs.insert(testCase.id).inserted else {
                throw CorpusConformanceError("duplicate corpus case '\(testCase.id)'")
            }
            guard let (grammar, precedence) = grammars[testCase.grammar] else {
                throw CorpusConformanceError(
                    "unknown grammar '\(testCase.grammar)' for '\(testCase.id)'"
                )
            }

            let parser = LRParser(grammar: grammar, algorithm: .lalr, precedence: precedence)
            let stream = NormalizedTokenStream(kinds: testCase.expectedTokenKinds)
            do {
                let result = try parser.parseOutcome(
                    stream: stream,
                    recovery: .localRepair(maxEdits: 8)
                )
                return GrammarREPLCorpusObservation(
                    id: testCase.id,
                    status: normalizedStatus(result.status),
                    root: result.tree?.root?.name,
                    diagnostics: result.diagnostics.count,
                    recoveryEdits: result.recoveryEdits.count
                )
            } catch {
                return GrammarREPLCorpusObservation(
                    id: testCase.id,
                    status: "rejected",
                    root: nil,
                    diagnostics: 1,
                    recoveryEdits: 0
                )
            }
        }
    }

    private static func normalizedStatus(_ status: ParseStatus) -> String {
        switch status {
        case .accepted: "accepted"
        case .recovered: "acceptedWithRecovery"
        case .rejected: "rejected"
        }
    }

    private static func makeGrammar(
        _ model: CorpusGrammar
    ) throws -> (Grammar, LRPrecedenceSpecification?) {
        let terminalNames = Set(model.terminals)
        let grammar = Grammar(
            productions: model.productions.map { production in
                Production(
                    goal: NonTerminal(name: production.lhs),
                    rule: production.rhs.map { symbol in
                        terminalNames.contains(symbol)
                            ? .terminal(Terminal(string: symbol))
                            : .nonTerminal(NonTerminal(name: symbol))
                    }
                )
            },
            start: NonTerminal(name: model.start),
            lexicalTokens: [:]
        )

        guard !model.precedence.isEmpty else { return (grammar, nil) }
        let levels = try model.precedence.enumerated().map { index, level in
            guard let associativity = LRAssociativity(rawValue: level.associativity) else {
                throw CorpusConformanceError(
                    "unknown associativity '\(level.associativity)' in grammar '\(model.id)'"
                )
            }
            return LRPrecedenceLevel(
                index + 1,
                associativity: associativity,
                terminals: Set(level.terminals.map { Terminal(string: $0) })
            )
        }
        return (grammar, LRPrecedenceSpecification(levels: levels))
    }
}

private struct Corpus: Decodable {
    let schemaVersion: Int
    let grammars: [CorpusGrammar]
    let cases: [CorpusCase]
}

private struct CorpusGrammar: Decodable {
    let id: String
    let start: String
    let terminals: [String]
    let productions: [CorpusProduction]
    let precedence: [CorpusPrecedence]
}

private struct CorpusProduction: Decodable {
    let lhs: String
    let rhs: [String]
}

private struct CorpusPrecedence: Decodable {
    let associativity: String
    let terminals: [String]
}

private struct CorpusCase: Decodable {
    let id: String
    let grammar: String
    let expectedTokenKinds: [String]
}

private struct NormalizedTokenStream: TokenStream {
    let source: String
    let values: [(Terminal, Range<String.Index>)]

    var count: Int { values.count }

    init(kinds: [String]) {
        source = kinds.joined(separator: " ")
        var cursor = source.startIndex
        var result: [(Terminal, Range<String.Index>)] = []
        result.reserveCapacity(kinds.count)
        for kind in kinds {
            let end = source.index(cursor, offsetBy: kind.count)
            result.append((Terminal(string: kind), cursor..<end))
            cursor = end == source.endIndex ? end : source.index(after: end)
        }
        values = result
    }

    func terminal(at position: Int) throws -> (terminal: Terminal, range: Range<String.Index>) {
        values[position]
    }
}

private struct CorpusConformanceError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
