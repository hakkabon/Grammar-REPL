//
//  Session.swift
//  Grammar-REPL
//
//  Created by Ulf Akerstedt-Inoue on 2026/07/66.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import Parser
import LR_Parsing

public struct LoadedGrammar {
    public let url: URL
    public let notation: REPLNotation
    public let start: String?
    public let grammar: Grammar
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

    public init() {}

    public mutating func load(_ grammar: LoadedGrammar) {
        loaded = grammar
        analysis = GrammarAnalysis(grammar: grammar.grammar)
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

    private mutating func invalidateDerivedState(clearInput: Bool) {
        if clearInput { lastInput = nil }
        lastTrees = []
        automaton = nil
        lastTrace = []
    }
}
