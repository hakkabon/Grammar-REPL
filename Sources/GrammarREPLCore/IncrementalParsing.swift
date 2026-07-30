import Foundation
import Grammar
import Parser
import LR_Parsing

public struct IncrementalParseMetrics: Codable, Equatable {
    public let commonPrefixUTF16: Int
    public let commonSuffixUTF16: Int
    public let invalidatedUTF16: WorkbenchSourceRange
    public let reusableTraceCheckpoints: Int
    public let performedFullValidation: Bool
}

public struct IncrementalParseResult {
    public let outcome: LRParseResult
    public let metrics: IncrementalParseMetrics
}

/// An observable incremental-parsing prototype. It computes edit invalidation
/// and reusable LR trace checkpoints, while deliberately validating the result
/// with the normal parser until LR-Parsing exposes resumable stack checkpoints.
public struct IncrementalLRSession {
    public let grammar: Grammar
    public let algorithm: LRParser.Algorithm
    public let precedence: LRPrecedenceSpecification?
    private var previousSource: String?
    private var previousOutcome: LRParseResult?

    public init(grammar: Grammar, algorithm: LRParser.Algorithm = .lalr, precedence: LRPrecedenceSpecification? = nil) {
        self.grammar = grammar; self.algorithm = algorithm; self.precedence = precedence
    }

    public mutating func parse(_ source: String, recovery: RecoveryPolicy = .none) throws -> IncrementalParseResult {
        if source == previousSource, let outcome = previousOutcome {
            let count = source.utf16.count
            return .init(outcome: outcome, metrics: .init(commonPrefixUTF16: count, commonSuffixUTF16: 0, invalidatedUTF16: .init(location: count, length: 0), reusableTraceCheckpoints: outcome.trace.count, performedFullValidation: false))
        }
        let old = previousSource ?? ""
        let prefix = commonPrefix(old, source)
        let suffix = commonSuffix(old, source, excludingPrefix: prefix)
        let prefixText = String(decoding: source.utf16.prefix(prefix), as: UTF16.self)
        let reusable = previousOutcome?.trace.filter { $0.tokenIndex <= tokenBoundaryCount(prefixText) }.count ?? 0
        let outcome = try LRParser(grammar: grammar, algorithm: algorithm, precedence: precedence).parseOutcome(source, recovery: recovery, tracing: true)
        previousSource = source
        previousOutcome = outcome
        return .init(outcome: outcome, metrics: .init(commonPrefixUTF16: prefix, commonSuffixUTF16: suffix, invalidatedUTF16: .init(location: prefix, length: max(0, source.utf16.count - prefix - suffix)), reusableTraceCheckpoints: reusable, performedFullValidation: true))
    }

    private func commonPrefix(_ left: String, _ right: String) -> Int {
        zip(left.utf16, right.utf16).prefix { $0 == $1 }.count
    }

    private func commonSuffix(_ left: String, _ right: String, excludingPrefix prefix: Int) -> Int {
        let maximum = min(left.utf16.count, right.utf16.count) - prefix
        return zip(left.utf16.reversed(), right.utf16.reversed()).prefix(maxLength: maximum) { $0 == $1 }.count
    }

    private func tokenBoundaryCount(_ prefix: String) -> Int { prefix.split(whereSeparator: \.isWhitespace).count }
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
