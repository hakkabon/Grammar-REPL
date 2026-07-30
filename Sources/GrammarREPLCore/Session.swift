import Foundation
import Grammar
import Parser
import LR_Parsing

public struct LoadedGrammar {
    public let url: URL
    public let notation: REPLNotation
    public let start: String?
    public let grammar: Grammar
    public let source: String?
    public let directives: GrammarDirectiveSet

    public init(url: URL, notation: REPLNotation, start: String?, grammar: Grammar, source: String? = nil, directives: GrammarDirectiveSet = .init()) {
        self.url = url
        self.notation = notation
        self.start = start
        self.grammar = grammar
        self.source = source
        self.directives = directives
    }
}

public struct REPLSession {
    public private(set) var loaded: LoadedGrammar?
    public private(set) var parser: REPLParser = .earley
    public private(set) var lastInput: String?
    public private(set) var lastTrees: [ParseTree] = []
    public private(set) var analysis: GrammarAnalysis?
    public private(set) var automaton: LRAutomaton?
    public private(set) var traceEnabled = false
    public private(set) var lastTrace: [LRParserTraceEvent] = []
    public private(set) var precedenceLevels: [LRPrecedenceLevel] = []
    public private(set) var resolutionPolicy: LRStandardConflictPolicy?
    public var precedence: LRPrecedenceSpecification? {
        precedenceLevels.isEmpty ? nil : LRPrecedenceSpecification(levels: precedenceLevels)
    }

    public init() {}

    public mutating func load(_ grammar: LoadedGrammar) {
        loaded = grammar
        analysis = GrammarAnalysis(grammar: grammar.grammar)
        precedenceLevels = grammar.directives.precedence.levels
        resolutionPolicy = nil
        invalidateDerivedState(clearInput: true)
    }

    public mutating func selectParser(_ value: REPLParser) {
        guard value != parser else { return }
        parser = value
        lastTrees = []
        automaton = nil
        lastTrace = []
    }

    public mutating func storeParse(input: String, trees: [ParseTree]) {
        lastInput = input
        lastTrees = trees
    }

    public mutating func storeAutomaton(_ value: LRAutomaton) { automaton = value }
    public mutating func setTraceEnabled(_ value: Bool) { traceEnabled = value }
    public mutating func storeTrace(_ value: [LRParserTraceEvent]) { lastTrace = value }
    public mutating func clearTrace() { lastTrace = [] }
    public mutating func setPrecedence(_ level: LRPrecedenceLevel) {
        precedenceLevels.removeAll { $0.precedence.level == level.precedence.level }
        precedenceLevels.append(level)
        precedenceLevels.sort { $0.precedence.level < $1.precedence.level }
        invalidateDerivedState(clearInput: false)
    }
    public mutating func clearPrecedence() {
        precedenceLevels = []
        invalidateDerivedState(clearInput: false)
    }
    public mutating func setResolutionPolicy(_ policy: LRStandardConflictPolicy?) {
        resolutionPolicy = policy
        invalidateDerivedState(clearInput: false)
    }

    private mutating func invalidateDerivedState(clearInput: Bool) {
        if clearInput { lastInput = nil }
        lastTrees = []
        automaton = nil
        lastTrace = []
    }
}
