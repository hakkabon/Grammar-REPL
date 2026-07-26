import Testing
import Foundation
import Grammar
@testable import GrammarREPLCore

@Suite("Command decoding")
struct CommandTests {
    @Test func decodesLRCommands() {
        #expect(REPLCommand.decode(":conflicts") == .conflicts)
        #expect(REPLCommand.decode(":state 12") == .state(12))
        #expect(REPLCommand.decode(":explain 2") == .explain(2))
        #expect(REPLCommand.decode(":parser lalr") == .parser(.lalr))
    }

    @Test func decodesQuotedLoadAndPlainInput() {
        #expect(REPLCommand.decode(":load \"a path/g.bnf\" S") == .load(path: "a path/g.bnf", start: "S"))
        #expect(REPLCommand.decode("id + id") == .parse("id + id"))
    }
}

@Suite("Session invalidation")
struct SessionTests {
    @Test func parserChangeInvalidatesTreesAndAutomatonButRetainsInput() throws {
        var session = REPLSession()
        let grammar = try Grammar(bnf: "<S> ::= \"a\"", start: "S")
        session.load(LoadedGrammar(url: URL(fileURLWithPath: "/tmp/a.bnf"), notation: .bnf, start: "S", grammar: grammar))
        session.storeParse(input: "a", trees: [.node(grammar.start, children: [])])
        session.selectParser(.lalr)
        #expect(session.loaded != nil)
        #expect(session.lastInput == "a")
        #expect(session.lastTrees.isEmpty)
        #expect(session.automaton == nil)
    }

    @Test func loadClearsOldParseState() throws {
        var session = REPLSession()
        let grammar = try Grammar(bnf: "<S> ::= \"a\"", start: "S")
        session.storeParse(input: "old", trees: [.node(grammar.start, children: [])])
        session.load(LoadedGrammar(url: URL(fileURLWithPath: "/tmp/a.bnf"), notation: .bnf, start: "S", grammar: grammar))
        #expect(session.lastInput == nil)
        #expect(session.lastTrees.isEmpty)
        #expect(session.analysis != nil)
    }
}

@Suite("Shared LL analysis")
struct AnalysisTests {
    @Test func findsPredictionConflict() throws {
        let grammar = try Grammar(bnf: "<S> ::= \"a\" | \"a\" \"b\"", start: "S")
        let analysis = GrammarAnalysis(grammar: grammar)
        #expect(analysis.llConflicts.count == 1)
        #expect(!analysis.llConflicts[0].lookaheads.isEmpty)
        #expect(analysis.predictionSets.count == 2)
    }

    @Test func reportsDisjointGrammar() throws {
        let grammar = try Grammar(bnf: "<S> ::= \"a\" | \"b\"", start: "S")
        #expect(GrammarAnalysis(grammar: grammar).llConflicts.isEmpty)
    }
}
