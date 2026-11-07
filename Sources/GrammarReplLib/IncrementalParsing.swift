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
    /// The package-owned checkpoint runtime and positioned compatibility parse
    /// agreed on acceptance and exact repair count.
    public let runtimeConverged: Bool

    public var incrementalInvalidatedRange: IncrementalParsing.SourceRange {
        .init(location: invalidatedUTF16.location, length: invalidatedUTF16.length)
    }

    public var incrementalExecutionEvidence: IncrementalParsing.IncrementalExecutionEvidence {
        nativeExecutionEvidence
    }

    private enum CodingKeys: String, CodingKey {
        case commonPrefixUTF16
        case commonSuffixUTF16
        case invalidatedUTF16
        case reusableTraceCheckpoints
        case performedFullValidation
        case nativeExecutionEvidence
        case runtimeConverged
    }

    public init(
        commonPrefixUTF16: Int,
        commonSuffixUTF16: Int,
        invalidatedUTF16: WorkbenchSourceRange,
        reusableTraceCheckpoints: Int,
        performedFullValidation: Bool,
        nativeExecutionEvidence: IncrementalExecutionEvidence,
        runtimeConverged: Bool
    ) {
        self.commonPrefixUTF16 = commonPrefixUTF16
        self.commonSuffixUTF16 = commonSuffixUTF16
        self.invalidatedUTF16 = invalidatedUTF16
        self.reusableTraceCheckpoints = reusableTraceCheckpoints
        self.performedFullValidation = performedFullValidation
        self.nativeExecutionEvidence = nativeExecutionEvidence
        self.runtimeConverged = runtimeConverged
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commonPrefixUTF16 = try container.decode(Int.self, forKey: .commonPrefixUTF16)
        commonSuffixUTF16 = try container.decode(Int.self, forKey: .commonSuffixUTF16)
        invalidatedUTF16 = try container.decode(WorkbenchSourceRange.self, forKey: .invalidatedUTF16)
        reusableTraceCheckpoints = try container.decode(Int.self, forKey: .reusableTraceCheckpoints)
        performedFullValidation = try container.decode(Bool.self, forKey: .performedFullValidation)
        nativeExecutionEvidence = try container.decode(
            IncrementalExecutionEvidence.self,
            forKey: .nativeExecutionEvidence
        )
        runtimeConverged = try container.decodeIfPresent(
            Bool.self,
            forKey: .runtimeConverged
        ) ?? false
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
            return .init(outcome: outcome, metrics: .init(commonPrefixUTF16: count, commonSuffixUTF16: 0, invalidatedUTF16: .init(location: count, length: 0), reusableTraceCheckpoints: native.reusedFrameCount, performedFullValidation: false, nativeExecutionEvidence: native.evidence, runtimeConverged: Self.converged(native: native.result, positioned: outcome)))
        }
        let old = previousSnapshot?.text ?? ""
        let prefix = commonPrefix(old, source)
        let suffix = commonSuffix(old, source, excludingPrefix: prefix)
        let outcome = try parser.parseOutcome(source, recovery: recovery, tracing: true)
        previousSnapshot = snapshot
        previousOutcome = outcome
        return .init(outcome: outcome, metrics: .init(commonPrefixUTF16: prefix, commonSuffixUTF16: suffix, invalidatedUTF16: .init(location: prefix, length: max(0, source.utf16.count - prefix - suffix)), reusableTraceCheckpoints: native.reusedFrameCount, performedFullValidation: true, nativeExecutionEvidence: native.evidence, runtimeConverged: Self.converged(native: native.result, positioned: outcome)))
    }

    private func commonPrefix(_ left: String, _ right: String) -> Int {
        zip(left.utf16, right.utf16).prefix { $0 == $1 }.count
    }

    private func commonSuffix(_ left: String, _ right: String, excludingPrefix prefix: Int) -> Int {
        let maximum = min(left.utf16.count, right.utf16.count) - prefix
        return zip(left.utf16.reversed(), right.utf16.reversed()).prefix(maxLength: maximum) { $0 == $1 }.count
    }

    private static func converged(
        native: LRRuntimeResult,
        positioned: LRParseResult
    ) -> Bool {
        let nativeAccepted: Bool
        switch native.outcome {
        case .accepted: nativeAccepted = true
        case .rejected, .conflict, .looping: nativeAccepted = false
        }
        return nativeAccepted == (positioned.status != .rejected)
            && native.recoveryEdits.count == positioned.recoveryEdits.count
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
