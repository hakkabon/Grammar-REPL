import Testing
import Foundation
import Grammar
import LR_Parsing
@testable import GrammarReplLib

@Suite("Command decoding")
struct CommandTests {
    @Test func decodesLRCommands() {
        #expect(REPLCommand.decode(":conflicts") == .conflicts)
        #expect(REPLCommand.decode(":state 12") == .state(12))
        #expect(REPLCommand.decode(":explain 2") == .explain(2))
        #expect(REPLCommand.decode(":replay 2") == .replay(2))
        #expect(REPLCommand.decode(":parser lalr") == .parser(.lalr))
        #expect(REPLCommand.decode(":diagram state 3") == .diagram("state 3"))
        #expect(REPLCommand.decode(":export state:3 out.dot") == .export(artifact: "state:3", path: "out.dot"))
        #expect(REPLCommand.decode(":trace on") == .trace("on"))
        #expect(REPLCommand.decode(":trace") == .trace(nil))
        #expect(REPLCommand.decode(":identity state 4") == .identity("state 4"))
        #expect(REPLCommand.decode(":precedence 2 left + -") == .precedence("2 left + -"))
        #expect(REPLCommand.decode(":resolution reduce") == .resolution("reduce"))
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
        #expect(CommandCompletion.candidates(for: ":trace o", session: session) == ["off", "on"])
    }
}

@Suite("REPL parser tracing")
struct REPLTracingTests {
    @Test func traceCommandsControlSessionWithoutParsing() {
        var output: [String] = []
        let repl = GrammarREPL(output: { output.append($0) })
        repl.execute(.trace("on"))
        #expect(repl.session.traceEnabled)
        repl.execute(.trace(nil))
        #expect(output.last?.contains("No LR parser trace") == true)
        repl.execute(.trace("off"))
        #expect(!repl.session.traceEnabled)
    }

    @Test func parserChangeInvalidatesStoredTrace() throws {
        var session = REPLSession()
        let grammar = try Grammar(bnf: "<S> ::= \"a\"", start: "S")
        let trace = try LRParser(grammar: grammar, algorithm: .lalr).parseOutcome("a", tracing: true).trace
        session.storeTrace(trace)
        #expect(!session.lastTrace.isEmpty)
        session.selectParser(.lalr)
        #expect(session.lastTrace.isEmpty)
    }
}

@Suite("Conflict explanations")
struct ConflictExplanationTests {
    @Test func explanationRendersStructuredActionOrigins() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("grammar-repl-conflict-\(UUID().uuidString).bnf")
        try "<E> ::= <E> \"+\" <E> | \"id\"".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        var output: [String] = []
        let repl = GrammarREPL(output: { output.append($0) })
        repl.execute(.load(path: url.path, start: "E"))
        repl.execute(.parser(.lalr))
        repl.execute(.explain(1))

        let text = output.joined(separator: "\n")
        #expect(text.contains("Competing action origins:"))
        #expect(text.contains("Why:"))
        #expect(text.contains("Origin item:"))
        #expect(text.contains("shift to state"))
        #expect(text.contains("reduce by"))
        #expect(text.contains("Candidate ID:"))
        #expect(text.contains("Selected action:"))
        #expect(text.contains("Resolution:"))
    }

    @Test func replayReachesConflictDecision() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("grammar-repl-replay-\(UUID().uuidString).bnf")
        try "<E> ::= <E> \"+\" <E> | \"id\"".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        var output: [String] = []
        let repl = GrammarREPL(output: { output.append($0) })
        repl.execute(.load(path: url.path, start: "E"))
        repl.execute(.parser(.lalr))
        repl.execute(.replay(1))

        let text = output.joined(separator: "\n")
        #expect(text.contains("Replay conflict 1:"))
        #expect(text.contains("Reached conflict in state"))
        #expect(text.contains("Selected shift to state"))
        #expect(text.contains("unresolved fallback policy"))
    }

    @Test func precedenceCommandResolvesConflictAndEnablesParsing() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("grammar-repl-precedence-\(UUID().uuidString).bnf")
        try "<E> ::= <E> \"+\" <E> | \"id\"".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        var output: [String] = []
        let repl = GrammarREPL(output: { output.append($0) })
        repl.execute(.load(path: url.path, start: "E"))
        repl.execute(.parser(.lalr))
        repl.execute(.check)
        #expect(repl.session.automaton?.unresolvedConflicts.count == 1)
        repl.execute(.precedence("1 left +"))
        #expect(repl.session.automaton == nil)
        repl.execute(.check)
        repl.execute(.parse("id + id + id"))

        #expect(repl.session.automaton?.resolvedConflicts.count == 1)
        #expect(repl.session.automaton?.unresolvedConflicts.isEmpty == true)
        #expect(output.joined(separator: "\n").contains("Accepted by lalr"))
    }

    @Test func resolutionPolicyResolvesConflictAndInvalidatesArtifact() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("grammar-repl-policy-\(UUID().uuidString).bnf")
        try "<E> ::= <E> \"+\" <E> | \"id\"".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        var output: [String] = []
        let repl = GrammarREPL(output: { output.append($0) })
        repl.execute(.load(path: url.path, start: "E"))
        repl.execute(.parser(.lalr))
        repl.execute(.check)
        #expect(repl.session.automaton?.unresolvedConflicts.count == 1)
        repl.execute(.resolution("reduce"))
        #expect(repl.session.automaton == nil)
        repl.execute(.check)
        repl.execute(.explain(1))
        repl.execute(.parse("id + id + id"))

        #expect(repl.session.automaton?.resolvedConflicts.count == 1)
        #expect(repl.session.automaton?.unresolvedConflicts.isEmpty == true)
        let text = output.joined(separator: "\n")
        #expect(text.contains("policy preferReduce"))
        #expect(text.contains("Accepted by lalr"))
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
