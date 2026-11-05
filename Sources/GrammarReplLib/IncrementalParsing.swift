//
//  IncrementalParsing.swift
//  Grammar-REPL
//
//  Created by Ulf Akerstedt-Inoue on 2026/07/66.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import Parser
import LR_Parsing
import IncrementalParsing

public struct IncrementalParseMetrics: Codable, Equatable {
    public let commonPrefixUTF16: Int
    public let commonSuffixUTF16: Int
    public let invalidatedUTF16: WorkbenchSourceRange
    public let reusableTraceCheckpoints: Int
    public let performedFullValidation: Bool
    public let nativeExecutionEvidence: IncrementalExecutionEvidence

    public var incrementalInvalidatedRange: IncrementalParsing.SourceRange {
        .init(location: invalidatedUTF16.location, length: invalidatedUTF16.length)
    }

    public var incrementalExecutionEvidence: IncrementalParsing.IncrementalExecutionEvidence {
        nativeExecutionEvidence
    }
}

public struct IncrementalParseResult {
    public let outcome: LRParseResult
    public let metrics: IncrementalParseMetrics
}

/// Uses LR-Parsing's native resumable stack runtime. The normal positioned
/// parser is retained as a correctness and source-range projection until its
/// public tree adapter can consume runtime nodes directly.
public struct IncrementalLRSession {
    public let grammar: Grammar
    public let algorithm: LRParser.Algorithm
    public let precedence: LRPrecedenceSpecification?
    private var previousSnapshot: IncrementalParsing.SourceSnapshot?
    private var previousOutcome: LRParseResult?
    private let parser: LRParser
    private let runtime: LRIncrementalRuntime
    private let runtimeTable: LRRuntimeTable

    public init(grammar: Grammar, algorithm: LRParser.Algorithm = .lalr, precedence: LRPrecedenceSpecification? = nil) {
        self.grammar = grammar; self.algorithm = algorithm; self.precedence = precedence
        let parser = LRParser(
            grammar: grammar, algorithm: algorithm, precedence: precedence)
        self.parser = parser
        runtime = LRIncrementalRuntime()
        runtimeTable = parser.incrementalRuntimeTable()
    }

    public mutating func parse(_ source: String, recovery: RecoveryPolicy = .none) throws -> IncrementalParseResult {
        let revision = try previousSnapshot?.revision.successor()
            ?? IncrementalParsing.SourceRevision(0)
        return try parse(
            .init(text: source, revision: revision), recovery: recovery)
    }

    public mutating func parse(
        _ snapshot: IncrementalParsing.SourceSnapshot,
        recovery: RecoveryPolicy = .none
    ) throws -> IncrementalParseResult {
        let source = snapshot.text
        let tokens = try parser.incrementalRuntimeTokens(for: source)
        let runtimeRecovery: LRRuntimeRecovery = switch recovery {
        case .none: .disabled
        case .localRepair(let maximum): .init(maximumDiagnostics: maximum)
        case .panic: .init(maximumDiagnostics: 32)
        }
        let native = runtime.parse(
            tokens, table: runtimeTable, recovery: runtimeRecovery)
        if source == previousSnapshot?.text, let outcome = previousOutcome {
            let count = source.utf16.count
            previousSnapshot = snapshot
            return .init(outcome: outcome, metrics: .init(commonPrefixUTF16: count, commonSuffixUTF16: 0, invalidatedUTF16: .init(location: count, length: 0), reusableTraceCheckpoints: native.reusedFrameCount, performedFullValidation: false, nativeExecutionEvidence: native.evidence))
        }
        let old = previousSnapshot?.text ?? ""
        let prefix = commonPrefix(old, source)
        let suffix = commonSuffix(old, source, excludingPrefix: prefix)
        let outcome = try parser.parseOutcome(source, recovery: recovery, tracing: true)
        previousSnapshot = snapshot
        previousOutcome = outcome
        return .init(outcome: outcome, metrics: .init(commonPrefixUTF16: prefix, commonSuffixUTF16: suffix, invalidatedUTF16: .init(location: prefix, length: max(0, source.utf16.count - prefix - suffix)), reusableTraceCheckpoints: native.reusedFrameCount, performedFullValidation: true, nativeExecutionEvidence: native.evidence))
    }

    private func commonPrefix(_ left: String, _ right: String) -> Int {
        zip(left.utf16, right.utf16).prefix { $0 == $1 }.count
    }

    private func commonSuffix(_ left: String, _ right: String, excludingPrefix prefix: Int) -> Int {
        let maximum = min(left.utf16.count, right.utf16.count) - prefix
        return zip(left.utf16.reversed(), right.utf16.reversed()).prefix(maxLength: maximum) { $0 == $1 }.count
    }

}

private extension Sequence {
    func prefix(maxLength: Int, while predicate: (Element) throws -> Bool) rethrows -> [Element] {
        var result: [Element] = []
        for element in self {
            guard result.count < maxLength, try predicate(element) else { break }
            result.append(element)
        }
        return result
    }
}
