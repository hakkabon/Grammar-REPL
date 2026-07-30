import Testing
import Foundation
import Grammar
import LR_Parsing
@testable import GrammarREPLCore

@Suite("Command decoding")
struct CommandTests {
    @Test func decodesLRCommands() {
        #expect(REPLCommand.decode(":conflicts") == .conflicts(nil))
        #expect(REPLCommand.decode(":conflicts resolved") == .conflicts("resolved"))
        #expect(REPLCommand.decode(":state 12") == .state(12))
        #expect(REPLCommand.decode(":explain 2") == .explain(2))
        #expect(REPLCommand.decode(":replay 2") == .replay(2, branches: false))
        #expect(REPLCommand.decode(":replay 2 all") == .replay(2, branches: true))
        #expect(REPLCommand.decode(":decisions 4") == .decisions(4))
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
        repl.execute(.replay(1, branches: false))

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
        repl.execute(.conflicts("resolved"))
        repl.execute(.decisions(nil))
        repl.execute(.replay(1, branches: true))
        repl.execute(.parse("id + id + id"))

        #expect(repl.session.automaton?.resolvedConflicts.count == 1)
        #expect(repl.session.automaton?.unresolvedConflicts.isEmpty == true)
        let text = output.joined(separator: "\n")
        #expect(text.contains("policy preferReduce"))
        #expect(text.contains("Branch 1: force"))
        #expect(text.contains("Branch 2: force"))
        #expect(text.contains("Outcome:"))
        #expect(text.contains("origin(s), ID"))
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

    @Test func conflictRendererConnectsWitnessOriginsDecisionAndBranches() throws {
        let grammar = try Grammar(bnf: "<E> ::= <E> \"+\" <E> | \"id\"", start: "E")
        let artifact = LRParser(grammar: grammar, algorithm: .lalr).generate()
        let conflict = try #require(artifact.allConflicts.first)
        let rendered = try LRConflictDOTRenderer().render(conflict, in: artifact)

        #expect(rendered.format == .dot)
        #expect(rendered.content.hasPrefix("digraph LRConflictExplanation"))
        #expect(rendered.content.contains("Automaton and witness path"))
        #expect(rendered.content.contains("Competing action origins"))
        #expect(rendered.content.contains("Candidate ID:"))
        #expect(rendered.content.contains("Decision [unresolved]"))
        #expect(rendered.content.contains("[selected]"))
        #expect(rendered.content.contains("Branch outcome:"))
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

@Suite("Workbench artifact serialization")
struct SerializationTests {
    @Test func roundTripsVersionedStableArtifact() throws {
        let grammar = try Grammar(bnf: "<S> ::= \"a\"", start: "S")
        let automaton = LRParser(grammar: grammar, algorithm: .lalr).generate()
        let envelope = WorkbenchArtifactEnvelope(sourceRevision: 7, grammar: grammar, analysis: GrammarAnalysis(grammar: grammar), automaton: automaton, generatedAt: Date(timeIntervalSince1970: 0))
        let data = try envelope.json()
        let decoded = try WorkbenchArtifactEnvelope.decode(data)
        #expect(decoded == envelope)
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.lr?.states.first?.id.hasPrefix("state:") == true)
        #expect(String(decoding: data, as: UTF8.self).contains("\"schemaVersion\" : 1"))
    }
}

@Suite("Embedded grammar directives")
struct DirectiveTests {
    @Test func declarationsAreRemovedAndResolveConflicts() throws {
        let source = "%left \"+\"\n%E ::= deliberately invalid"
        #expect(throws: GrammarDirectiveError.self) { try GrammarDirectiveParser.parse(source) }

        let valid = "%left \"+\"\n<E> ::= <E> \"+\" <E> | \"id\""
        let (grammar, directives) = try WorkbenchSourceLoader.load(valid, configuration: .init(notation: .bnf, start: "E"))
        let artifact = LRParser(grammar: grammar, algorithm: .lalr, precedence: directives.precedence).generate()
        #expect(directives.precedence.levels.count == 1)
        #expect(artifact.unresolvedConflicts.isEmpty)
        #expect(artifact.resolvedConflicts.count == 1)
    }
}

@Suite("Conflict minimization and performance harness")
struct WorkbenchAnalysisToolTests {
    @Test func minimizedWitnessStillReachesConflict() throws {
        let grammar = try Grammar(bnf: "<E> ::= <E> \"+\" <E> | \"id\"\n<Unused> ::= \"unused\"", start: "E")
        let automaton = LRParser(grammar: grammar, algorithm: .lalr).generate()
        let conflict = try #require(automaton.allConflicts.first)
        let result = LRConflictMinimizer.minimize(conflict, in: automaton)
        let probe = LRConflict(kind: conflict.kind, state: conflict.state, lookahead: conflict.lookahead, actions: conflict.actions, witness: result.minimizedWitness, identity: conflict.identity, candidates: conflict.candidates, decision: conflict.decision)
        #expect(result.minimizedWitness.count <= result.originalWitness.count)
        #expect(automaton.replay(probe).reachedConflict)
        #expect(!result.relevantProductions.isEmpty)

        let reduced = LRConflictMinimizer.minimizeGrammar(reproducing: conflict, grammar: grammar, algorithm: .lalr)
        #expect(reduced.grammar.productions.count < grammar.productions.count)
        #expect(reduced.removedProductionIDs.contains { $0.rawValue.contains("Unused") })
        #expect(!LRParser(grammar: reduced.grammar, algorithm: .lalr).generate().allConflicts.isEmpty)
    }

    @Test func benchmarkRecordsStructuralAndTimingObservations() throws {
        let grammar = try Grammar(bnf: "<S> ::= \"a\" <S> | \"b\"", start: "S")
        let report = LRBenchmarkHarness.measure(grammar: grammar, iterations: 1)
        #expect(report.samples.count == LRParser.Algorithm.allCases.count)
        #expect(report.maximumStateCount > 0)
        #expect(report.samples.allSatisfy { $0.transitionCount > 0 })
    }
}

@Suite("Incremental parsing prototype")
struct IncrementalParsingTests {
    @Test func reportsInvalidationAndCachesUnchangedParse() throws {
        let grammar = try Grammar(bnf: "<E> ::= <E> \"+\" \"id\" | \"id\"", start: "E")
        var session = IncrementalLRSession(grammar: grammar)
        let first = try session.parse("id + id")
        let unchanged = try session.parse("id + id")
        let edited = try session.parse("id + id + id")
        #expect(first.metrics.performedFullValidation)
        #expect(!unchanged.metrics.performedFullValidation)
        #expect(unchanged.metrics.invalidatedUTF16.length == 0)
        #expect(edited.metrics.commonPrefixUTF16 > 0)
        #expect(edited.metrics.performedFullValidation)
        #expect(edited.outcome.tree != nil)
    }
}

@Suite("Editor and language service")
struct LanguageServiceTests {
    @Test func documentLifecycleProducesRevisionedArtifactsAndNavigation() throws {
        let uri = URL(string: "file:///workspace/expression.bnf")!
        let source = "%left \"+\"\n<E> ::= <E> \"+\" <E> | \"id\""
        let server = GrammarLanguageServer()
        let opened = server.didOpen(uri: uri, text: source, version: 1, configuration: .init(notation: .bnf, start: "E"))
        #expect(opened.artifact?.sourceRevision == 1)
        #expect(opened.artifact?.lr?.conflicts.first?.status == "resolved")
        #expect(try server.completion(uri: uri, prefix: "E").map(\.label) == ["E"])
        #expect(try server.definition(uri: uri, nonterminal: "E") != nil)

        let changed = try server.didChange(uri: uri, version: 2, changes: [.init(text: "<S> ::= \"a\"")])
        #expect(changed.revision == 2)
        #expect(changed.artifact == nil) // BNF start E no longer exists.
        #expect(try server.diagnostics(uri: uri).contains { $0.severity == .error })
        server.didClose(uri: uri)
        #expect(throws: WorkbenchServiceError.self) { try server.artifact(uri: uri) }
    }
}
