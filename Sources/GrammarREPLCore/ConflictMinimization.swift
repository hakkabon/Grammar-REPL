import Grammar
import LR_Parsing

public struct LRConflictMinimizationResult {
    public let conflictIdentity: LRArtifactID
    public let originalWitness: [Terminal]
    public let minimizedWitness: [Terminal]
    public let relevantProductions: [LRProductionArtifact]
    public let attempts: Int
}

public enum LRConflictMinimizer {
    /// Delta-debugs the terminal witness while preserving reachability of the
    /// same semantic conflict cell. The production slice contains the origins
    /// directly participating in that cell and is useful for reproduction
    /// reports; it intentionally does not claim to be a complete grammar.
    public static func minimize(_ conflict: LRConflict, in automaton: LRAutomaton, maximumAttempts: Int = 1_000) -> LRConflictMinimizationResult {
        var witness = conflict.witness
        var attempts = 0
        var index = 0
        while index < witness.count, attempts < maximumAttempts {
            var candidate = witness
            candidate.remove(at: index)
            attempts += 1
            let probe = LRConflict(kind: conflict.kind, state: conflict.state, lookahead: conflict.lookahead, actions: conflict.actions, witness: candidate, identity: conflict.identity, candidates: conflict.candidates, decision: conflict.decision)
            if automaton.replay(probe).reachedConflict { witness = candidate }
            else { index += 1 }
        }
        let productionIDs = Set(conflict.candidates.map { $0.item.production.lrArtifactID })
        return LRConflictMinimizationResult(
            conflictIdentity: conflict.identity,
            originalWitness: conflict.witness,
            minimizedWitness: witness,
            relevantProductions: automaton.productions.filter { productionIDs.contains($0.identity) },
            attempts: attempts
        )
    }

    /// Greedily removes productions and regenerates the automaton after each
    /// attempt. A removal is retained only when a conflict with the same kind,
    /// lookahead, and action/production signature remains reproducible.
    public static func minimizeGrammar(
        reproducing conflict: LRConflict,
        grammar: Grammar,
        algorithm: LRParser.Algorithm,
        precedence: LRPrecedenceSpecification? = nil,
        maximumAttempts: Int = 1_000
    ) -> LRConflictGrammarMinimizationResult {
        let signature = ConflictSignature(conflict)
        var productions = grammar.productions
        var removed: [LRArtifactID] = []
        var attempts = 0
        var index = 0
        var reproduction = conflict
        while index < productions.count, attempts < maximumAttempts {
            let removedProduction = productions[index]
            let proposal = Array(productions[..<index]) + productions.dropFirst(index + 1)
            guard proposal.contains(where: { $0.goal == grammar.start }) else { index += 1; continue }
            attempts += 1
            let reduced = Grammar(productions: proposal, start: grammar.start, lexicalTokens: grammar.lexicalTokens)
            let artifact = LRParser(grammar: reduced, algorithm: algorithm, precedence: precedence).generate()
            if let matching = artifact.allConflicts.first(where: { ConflictSignature($0) == signature }) {
                productions = proposal
                removed.append(removedProduction.lrArtifactID)
                reproduction = matching
            } else { index += 1 }
        }
        return .init(
            grammar: Grammar(productions: productions, start: grammar.start, lexicalTokens: grammar.lexicalTokens),
            conflict: reproduction,
            removedProductionIDs: removed,
            attempts: attempts
        )
    }

    private struct ConflictSignature: Equatable {
        let kind: LRConflict.Kind
        let lookahead: Terminal
        let actions: [String]
        init(_ conflict: LRConflict) {
            kind = conflict.kind
            lookahead = conflict.lookahead
            actions = conflict.actions.map {
                switch $0 {
                case .shift: "shift"
                case .reduce(let production): "reduce:\(production.lrArtifactID.rawValue)"
                case .accept: "accept"
                }
            }.sorted()
        }
    }
}

public struct LRConflictGrammarMinimizationResult {
    public let grammar: Grammar
    public let conflict: LRConflict
    public let removedProductionIDs: [LRArtifactID]
    public let attempts: Int
}
