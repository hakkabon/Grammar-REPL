import Testing
import Foundation
import Grammar
import Parser
import LR_Parsing
@testable import GrammarReplLib

@Suite("Ecosystem corpus conformance")
struct EcosystemCorpusConformanceTests {
    @Test func evaluatesAcceptedRejectedAndRecoveredNormalizedInput() throws {
        let corpus = """
        {
          "schemaVersion": 2,
          "grammars": [{
            "id": "list",
            "start": "List",
            "terminals": ["OPEN", "VALUE", "COMMA", "CLOSE"],
            "precedence": [],
            "productions": [
              {"id": "list-root", "lhs": "List", "rhs": ["OPEN", "Items", "CLOSE"]},
              {"id": "list-item", "lhs": "Items", "rhs": ["VALUE"]}
            ]
          }],
          "cases": [
            {"id": "accepted", "grammar": "list", "input": "[1]", "expectedTokenKinds": ["OPEN", "VALUE", "CLOSE"], "expectedStatus": "accepted", "tags": ["literal"]},
            {"id": "rejected", "grammar": "list", "input": "?", "expectedTokenKinds": ["UNKNOWN"], "expectedStatus": "rejected", "tags": ["malformed-input"]},
            {"id": "recovered", "grammar": "list", "input": "[1,]", "expectedTokenKinds": ["OPEN", "VALUE", "COMMA", "CLOSE"], "expectedStatus": "acceptedWithRecovery", "tags": ["recovery"]}
          ]
        }
        """

        let observations = try GrammarREPLCorpusConformance.evaluate(Data(corpus.utf8))
        #expect(observations.map(\.id) == ["accepted", "rejected", "recovered"])
        #expect(observations[0].status == "accepted")
        #expect(observations[0].root == "List")
        #expect(observations[1].status == "rejected")
        #expect(observations[1].root == nil)
        #expect(observations[2].status == "acceptedWithRecovery")
        #expect(observations[2].diagnostics > 0)
        #expect(observations[2].recoveryEdits > 0)
    }

    @Test func rejectsUnknownGrammarReferences() {
        let corpus = """
        {
          "schemaVersion": 1,
          "grammars": [],
          "cases": [{"id": "case", "grammar": "missing", "input": "", "expectedTokenKinds": [], "expectedStatus": "accepted", "tags": ["epsilon"]}]
        }
        """
        #expect(throws: (any Error).self) {
            _ = try GrammarREPLCorpusConformance.evaluate(Data(corpus.utf8))
        }
    }

    @Test func versionFourReportsEveryEngineForComparisonCases() throws {
        let corpus = """
        {
          "schemaVersion": 4,
          "engines": [],
          "grammars": [{
            "id": "sample", "start": "S", "terminals": ["A"], "precedence": [],
            "productions": [{"id": "sample-a", "lhs": "S", "rhs": ["A"]}]
          }],
          "cases": [{
            "id": "comparison", "grammar": "sample", "input": "a",
            "expectedTokenKinds": ["A"], "expectedStatus": "accepted",
            "tags": ["engine-comparison"]
          }]
        }
        """

        let observation = try #require(
            GrammarREPLCorpusConformance.evaluate(Data(corpus.utf8)).first
        )
        #expect(observation.engines?.map(\.parser) == REPLParser.allCases)
        #expect(observation.engines?.allSatisfy { $0.status == "accepted" } == true)
        #expect(observation.engines?.filter { $0.forestNodes != nil }.count == 5)
        #expect(observation.engines?.allSatisfy(\.supported) == true)
    }
}

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
        #expect(REPLCommand.decode(":parser ll1") == .parser(.ll1))
        #expect(REPLCommand.decode(":parser earley-el") == .parser(.earleyEL))
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
        #expect(REPLCommand.decode(":compare \"a b\"") == .compare("a b"))
        #expect(REPLCommand.decode(":compare") == .compare(nil))
        #expect(REPLCommand.decode(":forest rnglr") == .forest(.rnglr))
        #expect(REPLCommand.decode(":playback lr1 12") == .playback(parser: .lr1, limit: 12))
        #expect(REPLCommand.decode(":playback 12") == .playback(parser: nil, limit: 12))
        #expect(REPLCommand.decode(":contract cyk") == .contract(.cyk))
        #expect(REPLCommand.decode(":experiment save \"my run.json\"") == .experimentSave("my run.json"))
        #expect(REPLCommand.decode(":experiment verify run.json") == .experimentVerify("run.json"))
        #expect(REPLCommand.decode(":experiment show run.json") == .experimentShow("run.json"))
    }
}

@Suite("Parser experiments")
struct ParserExperimentTests {
    private func checkContractInvariants(_ contract: ParseContractSnapshot) {
        #expect(!contract.engine.identity.isEmpty)
        #expect(!contract.engine.algorithm.isEmpty)
        #expect(contract.replay.map(\.step) == Array(contract.replay.indices))
        #expect(contract.replay.first?.kind == .start)
        switch contract.status {
        case .accepted, .recovered:
            #expect(contract.replay.last?.kind == .accept)
        case .rejected:
            #expect(contract.replay.last?.kind == .reject)
        }

        guard let forest = contract.forest else { return }
        let nodeIDs = forest.nodes.map(\.id)
        let nodeIDSet = Set(nodeIDs)
        #expect(nodeIDs == nodeIDs.sorted())
        #expect(nodeIDSet.count == nodeIDs.count)
        #expect(forest.edges == forest.edges.sorted())
        #expect(forest.edges.allSatisfy {
            nodeIDSet.contains($0.parent) && nodeIDSet.contains($0.child)
        })
        #expect(forest.roots.allSatisfy(nodeIDSet.contains))
        #expect(forest.ambiguityNodes.allSatisfy(nodeIDSet.contains))

        for node in forest.nodes {
            #expect(node.leftExtent >= 0)
            #expect(node.rightExtent >= node.leftExtent)
            if let pivot = node.pivot {
                #expect(pivot >= node.leftExtent && pivot <= node.rightExtent)
            }
            switch node.kind {
            case .token, .symbol:
                #expect(node.label != nil)
            case .intermediate, .packed:
                #expect(node.productionID != nil)
                #expect(node.position != nil)
            }
        }

        for ambiguity in forest.ambiguityNodes {
            let packedChildren = forest.edges.filter { edge in
                guard edge.parent == ambiguity,
                      let child = forest.nodes.first(where: { $0.id == edge.child }) else {
                    return false
                }
                return child.kind == .packed
            }
            #expect(packedChildren.count > 1)
        }
        #expect(contract.replay.compactMap(\.forestNodeID).allSatisfy(nodeIDSet.contains))
    }

    @Test func engineContractsRemainTruthfulAcrossRepeatedAmbiguityRuns() throws {
        let expression = NonTerminal(name: "Expression")
        let id = Terminal(string: "ID")
        let plus = Terminal(string: "PLUS")
        let grammar = Grammar(
            productions: [
                Production(goal: expression, rule: [
                    .nonTerminal(expression), .terminal(plus), .nonTerminal(expression),
                ]),
                Production(goal: expression, rule: [.terminal(id)]),
            ],
            start: expression,
            lexicalTokens: [:]
        )
        let precedence = LRPrecedenceSpecification(levels: [
            LRPrecedenceLevel(1, associativity: .left, terminals: [plus])
        ])
        let cases = [
            ("ID PLUS ID PLUS ID", 2),
            ("ID PLUS ID PLUS ID PLUS ID", 5),
        ]

        for (input, expectedDerivations) in cases {
            var baseline: [REPLParser: ParseContractSnapshot] = [:]
            var baselineFingerprints: [REPLParser: [String]] = [:]
            for _ in 0..<8 {
                let comparison = REPLParserExperiment.compare(
                    grammar: grammar, input: input, precedence: precedence
                )
                #expect(comparison.runs.count == REPLParser.allCases.count)
                for run in comparison.runs {
                    checkContractInvariants(run.contract)
                    if run.parser == .ll1 {
                        #expect(run.availability == .unsupported)
                        #expect(run.unsupportedReason != nil)
                        #expect(run.contract.status == .rejected)
                        continue
                    }
                    #expect(run.availability == .supported)
                    #expect(run.contract.status == .accepted)
                    if [.earley, .earleySL, .earleyEL, .cyk, .rnglr].contains(run.parser) {
                        #expect(run.trees.count == expectedDerivations)
                        #expect(run.contract.isAmbiguous)
                    } else {
                        #expect(run.trees.count == 1)
                        #expect(run.contract.forest == nil)
                    }
                    if let expected = baseline[run.parser] {
                        #expect(run.contract == expected)
                        #expect(run.treeFingerprints == baselineFingerprints[run.parser])
                    } else {
                        baseline[run.parser] = run.contract
                        baselineFingerprints[run.parser] = run.treeFingerprints
                    }
                }
            }
        }
    }

    @Test func comparesEveryEngineWithPortableArtifacts() throws {
        let grammar = try Grammar(bnf: "<S> ::= \"a\"", start: "S")
        let comparison = REPLParserExperiment.compare(grammar: grammar, input: "a")

        #expect(comparison.runs.map(\.parser) == REPLParser.allCases)
        #expect(comparison.runs.allSatisfy { $0.contract.status == .accepted })
        #expect(comparison.agreement == .complete)
        for parser in [REPLParser.earley, .earleySL, .earleyEL, .cyk, .rnglr] {
            let run = try #require(comparison.run(for: parser))
            #expect(run.contract.forest != nil)
            #expect(run.contract.forest?.nodes.contains { $0.productionID != nil } == true)
            #expect(run.contract.replay.last?.kind == .accept)
        }
        #expect(comparison.run(for: .lalr)?.contract.replay.contains { $0.kind == .applyProduction } == true)
        #expect(comparison.run(for: .ll1)?.availability == .supported)
        #expect(comparison.run(for: .ll1)?.contract.replay.contains { $0.kind == .consume } == true)
    }

    @Test func llCapabilityIsExplicitForUnsupportedGrammars() {
        let expression = NonTerminal(name: "Expression")
        let grammar = Grammar(
            productions: [
                Production(goal: expression, rule: [
                    .nonTerminal(expression), .terminal(Terminal(string: "PLUS")),
                    .nonTerminal(expression),
                ]),
                Production(goal: expression, rule: [.terminal(Terminal(string: "ID"))]),
            ],
            start: expression, lexicalTokens: [:]
        )
        let run = REPLParserExperiment.run(
            parser: .ll1, grammar: grammar, input: "ID PLUS ID"
        )
        #expect(run.availability == .unsupported)
        #expect(run.unsupportedReason?.contains("LL(1)") == true)
        #expect(run.failure == nil)
    }

    @Test func commandsExposeForestReplayAndJSONContract() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("grammar-repl-experiment-\(UUID().uuidString).bnf")
        try "<S> ::= \"a\"".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        var output: [String] = []
        let repl = GrammarREPL(output: { output.append($0) })
        repl.execute(.load(path: url.path, start: "S"))
        repl.execute(.compare("a"))
        repl.execute(.forest(.earley))
        repl.execute(.playback(parser: .lalr, limit: 4))
        repl.execute(.contract(.cyk))

        let text = output.joined(separator: "\n")
        #expect(text.contains("Agreement: complete."))
        #expect(text.contains("earley forest:"))
        #expect(text.contains("lalr replay (first 4):"))
        #expect(text.contains("\"schemaVersion\" : 1"))
        #expect(repl.session.lastComparison != nil)

        repl.execute(.parser(.rnglr))
        #expect(!repl.session.lastTrees.isEmpty)
    }
}

@Suite("Reproducible experiments")
struct ReproducibleExperimentTests {
    @Test func roundTripsAndReplaysEveryEngineDeterministically() throws {
        let grammar = try Grammar(bnf: "<S> ::= \"a\"", start: "S")
        let comparison = REPLParserExperiment.compare(grammar: grammar, input: "a")
        let first = try REPLExperimentDocument.capture(grammar: grammar, comparison: comparison)
        let second = try REPLExperimentDocument.capture(grammar: grammar, comparison: comparison)

        #expect(first.fingerprint == second.fingerprint)
        #expect(try first.json() == second.json())

        let decoded = try REPLExperimentDocument.decode(first.json())
        let verification = try decoded.verify()
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.engines == REPLParser.allCases)
        #expect(verification.matches)
        #expect(verification.engines.allSatisfy { $0.matches })
    }

    @Test func preservesUnsupportedCapabilitiesAndPrecedence() throws {
        let expression = NonTerminal(name: "Expression")
        let plus = Terminal(string: "PLUS")
        let grammar = Grammar(
            productions: [
                Production(goal: expression, rule: [
                    .nonTerminal(expression), .terminal(plus), .nonTerminal(expression),
                ]),
                Production(goal: expression, rule: [.terminal(Terminal(string: "ID"))]),
            ], start: expression, lexicalTokens: [:]
        )
        let precedence = LRPrecedenceSpecification(levels: [
            LRPrecedenceLevel(1, associativity: .left, terminals: [plus]),
        ])
        let comparison = REPLParserExperiment.compare(
            grammar: grammar, input: "ID PLUS ID PLUS ID", precedence: precedence
        )
        let document = try REPLExperimentDocument.capture(
            grammar: grammar, comparison: comparison, precedence: precedence
        )
        let decoded = try REPLExperimentDocument.decode(document.json())
        let verification = try decoded.verify()

        #expect(decoded.precedence.levels.count == 1)
        #expect(decoded.observations.first { $0.parser == .ll1 }?.availability == .unsupported)
        #expect(verification.matches)
    }

    @Test func rejectsTamperedArtifactBeforeReplay() throws {
        let grammar = try Grammar(bnf: "<S> ::= \"a\"", start: "S")
        let comparison = REPLParserExperiment.compare(grammar: grammar, input: "a")
        let document = try REPLExperimentDocument.capture(grammar: grammar, comparison: comparison)
        var object = try #require(JSONSerialization.jsonObject(with: document.json()) as? [String: Any])
        object["input"] = "b"
        let tampered = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: REPLExperimentError.self) {
            try REPLExperimentDocument.decode(tampered)
        }
    }

    @Test func replSavesShowsAndVerifiesPortableArtifact() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("grammar-repl-reproducible-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let grammarURL = directory.appendingPathComponent("grammar.bnf")
        let artifactURL = directory.appendingPathComponent("experiment.json")
        try "<S> ::= \"a\"".write(to: grammarURL, atomically: true, encoding: .utf8)

        var output: [String] = []
        let repl = GrammarREPL(output: { output.append($0) })
        repl.execute(.load(path: grammarURL.path, start: "S"))
        repl.execute(.compare("a"))
        repl.execute(.experimentSave(artifactURL.path))
        repl.execute(.experimentShow(artifactURL.path))
        repl.execute(.experimentVerify(artifactURL.path))

        #expect(FileManager.default.fileExists(atPath: artifactURL.path))
        #expect(output.contains { $0.hasPrefix("Saved experiment ") })
        #expect(output.contains { $0.hasPrefix("Experiment verified: ") })
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
