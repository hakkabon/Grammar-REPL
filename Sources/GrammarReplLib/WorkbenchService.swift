//
//  WorkbenchService.swift
//  Grammar-REPL
//
//  Created by Ulf Akerstedt-Inoue on 2026/07/66.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import Parser
import LR_Parsing

public struct WorkbenchSourceRange: Codable, Equatable, Sendable {
    public let location: Int
    public let length: Int
    public init(location: Int, length: Int) { self.location = location; self.length = length }
}

public enum WorkbenchDiagnosticSeverity: String, Codable, Sendable { case error, warning, information }

public struct WorkbenchDiagnostic: Codable, Equatable, Sendable {
    public let severity: WorkbenchDiagnosticSeverity
    public let message: String
    public let range: WorkbenchSourceRange?
    public let code: String
}

public struct GrammarDocumentConfiguration: Equatable {
    public var notation: REPLNotation
    public var start: String?
    public var algorithm: LRParser.Algorithm
    public init(notation: REPLNotation, start: String? = nil, algorithm: LRParser.Algorithm = .lalr) {
        self.notation = notation; self.start = start; self.algorithm = algorithm
    }
}

public struct WorkbenchDocumentSnapshot {
    public let uri: URL
    public let revision: Int
    public let source: String
    public let configuration: GrammarDocumentConfiguration
    public let diagnostics: [WorkbenchDiagnostic]
    public let artifact: WorkbenchArtifactEnvelope?
    public let generationNanoseconds: UInt64?
}

public struct WorkbenchLocation: Codable, Equatable, Sendable {
    public let uri: URL
    public let range: WorkbenchSourceRange
}

public enum WorkbenchSourceLoader {
    public static func load(_ source: String, configuration: GrammarDocumentConfiguration) throws -> (Grammar, GrammarDirectiveSet) {
        let value = try GrammarDirectiveParser.parse(source)
        let grammar: Grammar
        switch configuration.notation {
        case .gen: grammar = try Grammar(gen: value.grammarSource)
        case .bnf:
            guard let start = configuration.start, !start.isEmpty else { throw WorkbenchServiceError.missingStartSymbol(.bnf) }
            grammar = try Grammar(bnf: value.grammarSource, start: start)
        case .ebnf:
            guard let start = configuration.start, !start.isEmpty else { throw WorkbenchServiceError.missingStartSymbol(.ebnf) }
            grammar = try Grammar(ebnf: value.grammarSource, start: start)
        case .wsn:
            guard let start = configuration.start, !start.isEmpty else { throw WorkbenchServiceError.missingStartSymbol(.wsn) }
            grammar = try Grammar(wsn: value.grammarSource, start: start)
        }
        guard grammar.productions.contains(where: { $0.goal == grammar.start }) else {
            throw WorkbenchServiceError.invalidGrammar("The start symbol <\(grammar.start.name)> has no production.")
        }
        return (grammar, value.directives)
    }
}

public enum WorkbenchServiceError: Error, CustomStringConvertible {
    case missingDocument(URL)
    case staleRevision(expectedGreaterThan: Int, received: Int)
    case invalidEdit(WorkbenchSourceRange)
    case missingStartSymbol(REPLNotation)
    case invalidGrammar(String)

    public var description: String {
        switch self {
        case .missingDocument(let uri): "Document is not open: \(uri.absoluteString)"
        case .staleRevision(let current, let received): "Document revision \(received) is not newer than \(current)."
        case .invalidEdit(let range): "Invalid UTF-16 edit range \(range.location)..<\(range.location + range.length)."
        case .missingStartSymbol(let notation): "\(notation.rawValue.uppercased()) requires a start symbol."
        case .invalidGrammar(let message): message
        }
    }
}

/// Stateful, UI-independent document service. It is deliberately transport
/// neutral: an LSP server, web view bridge, or native workbench can all map
/// their document lifecycle onto this API.
public final class GrammarWorkbenchService {
    private struct Document {
        var source: String
        var revision: Int
        var configuration: GrammarDocumentConfiguration
        var snapshot: WorkbenchDocumentSnapshot
    }
    private var documents: [URL: Document] = [:]

    public init() {}

    @discardableResult
    public func open(uri: URL, source: String, revision: Int = 1, configuration: GrammarDocumentConfiguration) -> WorkbenchDocumentSnapshot {
        let snapshot = analyze(uri: uri, source: source, revision: revision, configuration: configuration)
        documents[uri] = Document(source: source, revision: revision, configuration: configuration, snapshot: snapshot)
        return snapshot
    }

    @discardableResult
    public func change(uri: URL, revision: Int, range: WorkbenchSourceRange? = nil, replacement: String) throws -> WorkbenchDocumentSnapshot {
        guard var document = documents[uri] else { throw WorkbenchServiceError.missingDocument(uri) }
        guard revision > document.revision else { throw WorkbenchServiceError.staleRevision(expectedGreaterThan: document.revision, received: revision) }
        if let range {
            guard let swiftRange = Range(NSRange(location: range.location, length: range.length), in: document.source) else { throw WorkbenchServiceError.invalidEdit(range) }
            document.source.replaceSubrange(swiftRange, with: replacement)
        } else { document.source = replacement }
        document.revision = revision
        document.snapshot = analyze(uri: uri, source: document.source, revision: revision, configuration: document.configuration)
        documents[uri] = document
        return document.snapshot
    }

    public func close(uri: URL) { documents[uri] = nil }
    public func snapshot(uri: URL) throws -> WorkbenchDocumentSnapshot {
        guard let value = documents[uri]?.snapshot else { throw WorkbenchServiceError.missingDocument(uri) }
        return value
    }

    public func completions(uri: URL, prefix: String) throws -> [String] {
        let snapshot = try snapshot(uri: uri)
        return (snapshot.artifact?.grammar.productions.map(\.goal) ?? []).filter { $0.hasPrefix(prefix) }.uniqued().sorted()
    }

    public func definition(uri: URL, nonterminal: String) throws -> WorkbenchLocation? {
        let source = try snapshot(uri: uri).source as NSString
        for spelling in ["<\(nonterminal)>", nonterminal] {
            let range = source.range(of: spelling)
            if range.location != NSNotFound { return WorkbenchLocation(uri: uri, range: .init(location: range.location, length: range.length)) }
        }
        return nil
    }

    private func analyze(uri: URL, source: String, revision: Int, configuration: GrammarDocumentConfiguration) -> WorkbenchDocumentSnapshot {
        let started = ContinuousClock.now
        do {
            let (grammar, directives) = try WorkbenchSourceLoader.load(source, configuration: configuration)
            let analysis = GrammarAnalysis(grammar: grammar)
            let precedence = directives.precedence.levels.isEmpty ? nil : directives.precedence
            let automaton = LRParser(grammar: grammar, algorithm: configuration.algorithm, precedence: precedence).generate()
            var diagnostics = analysis.llConflicts.map { WorkbenchDiagnostic(severity: .warning, message: "LL(1) conflict in <\($0.nonterminal.name)> on \($0.lookaheads.map(\.description).sorted().joined(separator: ", "))", range: nil, code: "grammar.ll-conflict") }
            diagnostics += automaton.unresolvedConflicts.map { WorkbenchDiagnostic(severity: .warning, message: $0.description, range: nil, code: "grammar.lr-conflict") }
            return .init(uri: uri, revision: revision, source: source, configuration: configuration, diagnostics: diagnostics, artifact: .init(sourceRevision: revision, grammar: grammar, analysis: analysis, automaton: automaton), generationNanoseconds: nanoseconds(since: started))
        } catch {
            return .init(uri: uri, revision: revision, source: source, configuration: configuration, diagnostics: [.init(severity: .error, message: String(describing: error), range: nil, code: "grammar.invalid")], artifact: nil, generationNanoseconds: nanoseconds(since: started))
        }
    }

    private func nanoseconds(since start: ContinuousClock.Instant) -> UInt64 {
        let value = start.duration(to: .now).components
        return UInt64(max(0, value.seconds)) * 1_000_000_000 + UInt64(max(0, value.attoseconds / 1_000_000_000))
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted
        }
    }
}
