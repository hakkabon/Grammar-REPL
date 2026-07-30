//
//  Analysis.swift
//  Grammar-REPL
//
//  Created by Ulf Akerstedt-Inoue on 2026/07/66.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Grammar

public struct LLConflict: Hashable {
    public let nonterminal: NonTerminal
    public let first: Production
    public let second: Production
    public let lookaheads: Set<Symbol>
}

public struct GrammarAnalysis {
    public let first: [Symbol: Set<Symbol>]
    public let follow: [NonTerminal: Set<Symbol>]
    public let predictionSets: [Production: Set<Symbol>]
    public let llConflicts: [LLConflict]

    public init(grammar: Grammar) {
        let (first, follow) = grammar.firstAndFollow()
        self.first = first
        self.follow = follow
        var predictions: [Production: Set<Symbol>] = [:]
        for production in grammar.productions {
            predictions[production] = Self.predict(production, first: first, follow: follow, grammar: grammar)
        }
        predictionSets = predictions
        var conflicts: [LLConflict] = []
        for nonterminal in grammar.nonTerminals.sorted() {
            let productions = grammar.productions.filter { $0.goal == nonterminal }
            for left in productions.indices {
                for right in productions.indices where right > left {
                    let overlap = predictions[productions[left], default: []]
                        .intersection(predictions[productions[right], default: []])
                    if !overlap.isEmpty {
                        conflicts.append(LLConflict(nonterminal: nonterminal, first: productions[left], second: productions[right], lookaheads: overlap))
                    }
                }
            }
        }
        llConflicts = conflicts
    }

    private static func predict(_ production: Production, first: [Symbol: Set<Symbol>], follow: [NonTerminal: Set<Symbol>], grammar: Grammar) -> Set<Symbol> {
        var result = grammar.first(of: production.rule, using: first)
        let epsilon = Symbol.terminal(.meta(grammar.epsilon))
        if result.remove(epsilon) != nil || production.rule.isEmpty {
            result.formUnion(follow[production.goal] ?? [])
        }
        return result
    }
}
