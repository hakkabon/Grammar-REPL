import Foundation
import Grammar
import LR_Parsing

public struct LRBenchmarkSample: Codable, Equatable {
    public let algorithm: String
    public let iteration: Int
    public let generationNanoseconds: UInt64
    public let stateCount: Int
    public let transitionCount: Int
    public let conflictCount: Int
}

public struct LRBenchmarkReport: Codable, Equatable {
    public let samples: [LRBenchmarkSample]
    public var maximumStateCount: Int { samples.map(\.stateCount).max() ?? 0 }
    public var medianGenerationNanoseconds: UInt64 {
        let values = samples.map(\.generationNanoseconds).sorted()
        return values.isEmpty ? 0 : values[values.count / 2]
    }
}

/// A dependency-free benchmark harness suitable for XCTest/Testing, CI, and
/// workbench telemetry. It records observations but imposes no machine-specific
/// timing threshold unless the caller chooses to do so.
public enum LRBenchmarkHarness {
    public static func measure(grammar: Grammar, algorithms: [LRParser.Algorithm] = LRParser.Algorithm.allCases, iterations: Int = 3, precedence: LRPrecedenceSpecification? = nil) -> LRBenchmarkReport {
        var samples: [LRBenchmarkSample] = []
        for algorithm in algorithms {
            for iteration in 0..<max(1, iterations) {
                let start = ContinuousClock.now
                let artifact = LRParser(grammar: grammar, algorithm: algorithm, precedence: precedence).generate()
                let duration = start.duration(to: .now)
                let components = duration.components
                let nanoseconds = UInt64(max(0, components.seconds)) * 1_000_000_000 + UInt64(max(0, components.attoseconds / 1_000_000_000))
                samples.append(.init(algorithm: String(describing: algorithm), iteration: iteration, generationNanoseconds: nanoseconds, stateCount: artifact.states.count, transitionCount: artifact.transitions.count, conflictCount: artifact.allConflicts.count))
            }
        }
        return LRBenchmarkReport(samples: samples)
    }
}
