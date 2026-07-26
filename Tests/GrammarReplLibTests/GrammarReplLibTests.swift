import Testing
import Foundation
import Grammar
@testable import GrammarReplLib
//=======
//import LR_Parsing
//@testable import GrammarREPLCore
//>>>>>>> dev-branch:Tests/GrammarREPLCoreTests/GrammarREPLCoreTests.swift

@Suite("Command decoding")
struct CommandTests {
    @Test func decodesLRCommands() {
        #expect(REPLCommand.decode(":conflicts") == .conflicts)
        #expect(REPLCommand.decode(":state 12") == .state(12))
        #expect(REPLCommand.decode(":explain 2") == .explain(2))
        #expect(REPLCommand.decode(":parser lalr") == .parser(.lalr))
        #expect(REPLCommand.decode(":diagram state 3") == .diagram("state 3"))
        #expect(REPLCommand.decode(":export state:3 out.dot") == .export(artifact: "state:3", path: "out.dot"))
    }

    @Test func decodesQuotedLoadAndPlainInput() {
        #expect(REPLCommand.decode(":load \"a path/g.bnf\" S") == .load(path: "a path/g.bnf", start: "S"))
        #expect(REPLCommand.decode("id + id") == .parse("id + id"))
    }
}

@Suite("History and completion")
struct InteractiveTests {
    @Test func historyIsBoundedAndCollapsesAdjacentDuplicates() {
        var history = CommandHistory(capacity: 2)
        history.append(":help")
        history.append(":help")
        history.append(":check")
        history.append(":grammar")
        #expect(history.entries == [":check", ":grammar"])
    }

    @Test func completionUsesCommandsParsersAndGrammarSymbols() throws {
        var session = REPLSession()
        let grammar = try Grammar(bnf: "<start> ::= <value>\n<value> ::= \"a\"", start: "start")
        session.load(LoadedGrammar(url: URL(fileURLWithPath: "/tmp/a.bnf"), notation: .bnf, start: "start", grammar: grammar))
        #expect(CommandCompletion.candidates(for: ":conf", session: session) == [":conflicts"])
        #expect(CommandCompletion.candidates(for: ":parser la", session: session) == ["lalr"])
        #expect(CommandCompletion.candidates(for: ":first v", session: session) == ["value"])
    }
}

@Suite("Graphical artifact renderers")
struct ArtifactRendererTests {
    @Test func railroadRendererUsesLoadedGrammarSyntax() throws {
        let grammar = try Grammar(bnf: "<S> ::= \"a\" | \"b\"", start: "S")
        let rendered = try RailroadGrammarRenderer().render(grammar)
        #expect(rendered.format == .text)
        #expect(rendered.content.contains("Production: S"))
    }

    @Test func automatonRendererProducesDOT() throws {
        let grammar = try Grammar(bnf: "<S> ::= \"a\"", start: "S")
        let artifact = LRParser(grammar: grammar, algorithm: .lalr).generate()
        let rendered = try LRAutomatonDOTRenderer().render(artifact)
        #expect(rendered.format == .dot)
        #expect(rendered.content.hasPrefix("digraph LRAutomaton"))
        #expect(rendered.content.contains("->"))
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
