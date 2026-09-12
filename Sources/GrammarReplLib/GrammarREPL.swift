//
//  GrammarREPL.swift
//  Grammar-REPL
//
//  Created by Ulf Akerstedt-Inoue on 2026/07/66.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import Parser
import LR_Parsing
import RNGLR_Parser
import CYK_Parser
import Earley_Parser
import Earley_TableParser
import struct Compiler.ASTMapping
import struct Compiler.CompilerSemanticConvergenceReport
import struct Compiler.CompilerSemanticEngineInput
import enum Compiler.CompilerSemanticConvergence

public final class GrammarREPL {
    public private(set) var session = REPLSession()
    public private(set) var history = CommandHistory()
    private let output: (String) -> Void
    private let readCommand: (String, REPLSession) -> String?

    public init(
        output: @escaping (String) -> Void = { print($0) },
        readCommand: @escaping (String, REPLSession) -> String? = { prompt, _ in
            Swift.print(prompt, terminator: "")
            return readLine()
        }
    ) {
        self.output = output
        self.readCommand = readCommand
    }

    public func run() {
        output("Grammar REPL — type :help for commands")
        while true {
            guard let line = readCommand("grammar> ", session) else { break }
            history.append(line)
            if !execute(.decode(line)) { break }
        }
    }

    @discardableResult
    public func execute(_ command: REPLCommand) -> Bool {
        do {
            switch command {
            case .help: output(Self.help)
            case .quit: return false
            case .load(let path, let start): try load(path: path, start: start)
            case .reload: try reload()
            case .grammar: output(String(describing: try grammar()))
            case .parser(let parser): setParser(parser)
            case .check: try check()
            case .conflicts(let filter): try showConflicts(filter)
            case .decisions(let state): try showDecisions(state)
            case .state(let id): try showState(id)
            case .explain(let id): try explain(id)
            case .replay(let id, let branches): try replay(id, branches: branches)
            case .first(let name): try showFirst(name)
            case .follow(let name): try showFollow(name)
            case .predict(let name): try showPredict(name)
            case .parse(let input): try parseInput(input)
            case .tree(let index): try showTree(index)
            case .compare(let input): try compareInput(input)
            case .forest(let parser): try showForest(parser)
            case .playback(let parser, let limit): try showPlayback(parser, limit: limit)
            case .contract(let parser): try showContract(parser)
            case .experimentSave(let path): try saveExperiment(to: path)
            case .experimentVerify(let path): try verifyExperiment(at: path)
            case .experimentShow(let path): try showExperiment(at: path)
            case .semantics(let path): try configureSemantics(path)
            case .settings: showSettings()
            case .history:
                for (index, line) in history.entries.enumerated() { output("\(index + 1)  \(line)") }
            case .diagram(let specification): output(try renderArtifact(specification).content)
            case .export(let artifact, let path): try exportArtifact(artifact, to: path)
            case .trace(let argument): showTrace(argument)
            case .identity(let specification): try showIdentity(specification)
            case .precedence(let specification): try configurePrecedence(specification)
            case .resolution(let specification): try configureResolution(specification)
            case .unknown(let text): if !text.isEmpty { output("Unknown or incomplete command: \(text)\nType :help for usage.") }
            }
        } catch { output("Error: \(error)") }
        return true
    }

    private func load(path: String, start: String?) throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let notation = REPLNotation(rawValue: url.pathExtension.lowercased()) ?? .gen
        let text = try String(contentsOf: url, encoding: .utf8)
        let preprocessed = try GrammarDirectiveParser.parse(text)
        let value: Grammar
        switch notation {
        case .gen: value = try Grammar(gen: preprocessed.grammarSource)
        case .bnf:
            guard let start, !start.isEmpty else { throw Message("BNF requires a start rule: :load file.bnf start") }
            value = try Grammar(bnf: preprocessed.grammarSource, start: start)
        case .ebnf:
            guard let start, !start.isEmpty else { throw Message("EBNF requires a start rule: :load file.ebnf start") }
            value = try Grammar(ebnf: preprocessed.grammarSource, start: start)
        case .wsn:
            guard let start, !start.isEmpty else { throw Message("WSN requires a start rule: :load file.wsn start") }
            value = try Grammar(wsn: preprocessed.grammarSource, start: start)
        }
        session.load(LoadedGrammar(url: url, notation: notation, start: start, grammar: value, source: text, directives: preprocessed.directives))
        output("Loaded \(url.lastPathComponent): \(value.productions.count) productions, start <\(value.start.name)>.")
    }

    private func reload() throws {
        guard let loaded = session.loaded else { throw Message("No grammar is loaded.") }
        try load(path: loaded.url.path, start: loaded.start)
    }

    private func setParser(_ parser: REPLParser?) {
        guard let parser else {
            output("Parser: \(session.parser.rawValue). Available: \(REPLParser.allCases.map(\.rawValue).joined(separator: ", ")).")
            return
        }
        session.selectParser(parser)
        output("Parser set to \(parser.rawValue).")
    }

    private func check() throws {
        let value = try grammar()
        let analysis = session.analysis ?? GrammarAnalysis(grammar: value)
        output("Grammar: \(value.productions.count) productions, \(value.nonTerminals.count) nonterminals, \(value.terminals.count) terminals.")
        output(analysis.llConflicts.isEmpty ? "LL(1) prediction sets are disjoint." : "Found \(analysis.llConflicts.count) LL(1) prediction conflict(s).")
        if session.parser.lrAlgorithm != nil {
            let artifact = try automaton()
            output("\(session.parser.rawValue.uppercased()): \(artifact.states.count) states, \(artifact.resolvedConflicts.count) resolved and \(artifact.unresolvedConflicts.count) unresolved conflict(s).")
        }
    }

    private func showConflicts(_ filter: String?) throws {
        if session.parser.lrAlgorithm == nil {
            let conflicts: [LLConflict]
            if let cached = session.analysis { conflicts = cached.llConflicts }
            else { conflicts = GrammarAnalysis(grammar: try grammar()).llConflicts }
            guard !conflicts.isEmpty else { output("No LL(1) conflicts."); return }
            for (index, conflict) in conflicts.enumerated() {
                output("[\(index + 1)] <\(conflict.nonterminal.name)> on {\(render(conflict.lookaheads))}\n    \(conflict.first)\n    \(conflict.second)")
            }
            return
        }
        let artifact = try automaton()
        let all = artifact.allConflicts
        let visible: [(Int, LRConflict)]
        switch filter ?? "all" {
        case "all": visible = Array(all.enumerated())
        case "resolved": visible = all.enumerated().filter { $0.element.isResolved }
        case "unresolved": visible = all.enumerated().filter { !$0.element.isResolved }
        default: throw Message("Use :conflicts [all|resolved|unresolved].")
        }
        guard !visible.isEmpty else { output("No matching \(session.parser.rawValue.uppercased()) conflicts."); return }
        for (index, conflict) in visible {
            output("[\(index + 1)] [\(conflict.status.rawValue)] \(conflict)\n    witness: \(conflict.witness.map(\.description).joined(separator: " "))")
        }
    }

    private func showDecisions(_ requestedState: Int?) throws {
        let artifact = try automaton()
        if let requestedState, artifact.state(requestedState) == nil { throw Message("Unknown LR state \(requestedState).") }
        let states = requestedState.map { [$0] } ?? artifact.actionDecisions.keys.sorted()
        var count = 0
        for state in states {
            for (lookahead, decision) in (artifact.actionDecisions[state] ?? [:]).sorted(by: { $0.key.description < $1.key.description }) {
                let selected = decision.selectedAction.map(render) ?? "error"
                output("state \(state), lookahead \(lookahead): \(selected) [\(decision.status.rawValue)]\n    \(decision.resolution)\n    \(decision.candidates.count) origin(s), ID \(decision.identity)")
                count += 1
            }
        }
        if count == 0 { output(requestedState.map { "No ACTION decisions in state \($0)." } ?? "No ACTION decisions.") }
    }

    private func showState(_ requested: Int?) throws {
        guard let requested else { throw Message("Provide a state number: :state <number>") }
        guard let state = try automaton().state(requested) else { throw Message("Unknown LR state \(requested).") }
        output(state.description)
        let edges = try automaton().transitions.filter { $0.source == requested }
        for edge in edges { output("  on \(edge.symbol) → state \(edge.target)") }
    }

    private func explain(_ requested: Int?) throws {
        guard let requested, requested > 0 else { throw Message("Provide a one-based conflict number: :explain <number>") }
        let conflicts = try automaton().allConflicts
        guard conflicts.indices.contains(requested - 1) else { throw Message("Conflict number must be between 1 and \(conflicts.count).") }
        let conflict = conflicts[requested - 1]
        output("Conflict \(requested): \(conflict.kind.rawValue) in state \(conflict.state) on \(conflict.lookahead)")
        output("Stable ID: \(conflict.identity)")
        output("Shortest witness: \(conflict.witness.map(\.description).joined(separator: " "))")
        if let decision = conflict.decision {
            if let action = decision.selectedAction { output("Selected action: \(render(action))") }
            else { output("Selected action: error") }
            output("Status: \(decision.status.rawValue)")
            output("Resolution: \(decision.resolution)")
            output("Decision ID: \(decision.identity)")
        }
        output("Competing action origins:")
        for (index, candidate) in conflict.candidates.enumerated() {
            output("  [\(index + 1)] \(render(candidate.action))")
            output("      Why: \(candidate.reason)")
            output("      Origin item: \(candidate.item)")
            output("      Item ID: \(candidate.item.identity)")
            output("      Candidate ID: \(candidate.identity)")
        }
        if conflict.candidates.isEmpty {
            for (index, action) in conflict.actions.enumerated() { output("  [\(index + 1)] \(render(action))") }
        }
        if let state = try automaton().state(conflict.state) {
            output("State context [\(state.identity)]:")
            output(state.description)
        }
    }

    private func replay(_ requested: Int?, branches: Bool) throws {
        guard let requested, requested > 0 else { throw Message("Provide a one-based conflict number: :replay <number>") }
        let artifact = try automaton()
        let conflicts = artifact.allConflicts
        guard conflicts.indices.contains(requested - 1) else { throw Message("Conflict number must be between 1 and \(conflicts.count).") }
        let conflict = conflicts[requested - 1]
        let replay = artifact.replay(conflict)
        output("Replay conflict \(requested): \(conflict.identity)")
        output("Witness: \(conflict.witness.map(\.description).joined(separator: " "))")
        for step in replay.steps { output(step.description) }
        if replay.reachedConflict {
            output("Reached conflict in state \(conflict.state) on \(conflict.lookahead).")
            if let decision = replay.decision {
                if let action = decision.selectedAction { output("Selected \(render(action)) because \(decision.resolution).") }
                else { output("Selected an error ACTION because \(decision.resolution).") }
            }
        } else {
            output("Replay did not reach the conflict: \(replay.failure ?? "unknown reason").")
        }
        if branches, replay.reachedConflict {
            for (index, branch) in artifact.replayBranches(conflict).enumerated() {
                output("Branch \(index + 1): force \(render(branch.action))\(branch.wasSelected ? " [selected]" : "")")
                for step in branch.steps.dropFirst(replay.steps.count) { output("  \(step.description)") }
                output("  Outcome: \(branch.outcome)")
            }
        }
    }

    private func showFirst(_ name: String) throws {
        let nt = try findNonterminal(name)
        output("FIRST(<\(nt.name)>) = {\(render(session.analysis?.first[.nonTerminal(nt)] ?? []))}")
    }

    private func showFollow(_ name: String) throws {
        let nt = try findNonterminal(name)
        output("FOLLOW(<\(nt.name)>) = {\(render(session.analysis?.follow[nt] ?? []))}")
    }

    private func showPredict(_ name: String) throws {
        let nt = try findNonterminal(name)
        for (index, production) in try grammar().productions.filter({ $0.goal == nt }).enumerated() {
            output("[\(index + 1)] \(production)\n    PREDICT = {\(render(session.analysis?.predictionSets[production] ?? []))}")
        }
    }

    private func parseInput(_ input: String) throws {
        guard !input.isEmpty else { throw Message("Provide input after :parse.") }
        let grammar = try grammar()
        let trees: [ParseTree]
        switch session.parser {
        case .earley: trees = try EarleyParser(grammar: grammar).allSyntaxTrees(for: input)
        case .earleySL: trees = try EarleyTableParser(grammar: grammar).allSyntaxTrees(for: input)
        case .earleyEL: trees = try EarleyTableParser(grammar: grammar, useExtendedLookahead: true).allSyntaxTrees(for: input)
        case .cyk: trees = try CYKParser(grammar: grammar).allSyntaxTrees(for: input)
        case .rnglr: trees = try RNGLRParser(grammar: grammar).allSyntaxTrees(for: input)
        case .ll1:
            let run = REPLParserExperiment.run(parser: .ll1, grammar: grammar, input: input)
            guard run.availability == .supported else {
                throw Message(run.unsupportedReason ?? "Grammar is outside LL(1).")
            }
            trees = run.trees
        case .lr0, .slr, .lalr, .lr1:
            guard let algorithm = session.parser.lrAlgorithm else { throw Message("Missing LR algorithm.") }
            let outcome = try LRParser(grammar: grammar, algorithm: algorithm, precedence: session.precedence, resolutionPolicy: session.resolutionPolicy).parseOutcome(input, recovery: .localRepair(maxEdits: 2), tracing: session.traceEnabled)
            session.storeTrace(outcome.trace)
            for diagnostic in outcome.diagnostics { output(diagnostic.description) }
            for edit in outcome.recoveryEdits { output("Recovery: \(edit)") }
            trees = outcome.tree.map { [$0] } ?? []
            guard outcome.status != .rejected else { session.storeParse(input: input, trees: []); return }
        }
        session.storeParse(input: input, trees: trees)
        output("Accepted by \(session.parser.rawValue): \(trees.count) derivation(s).")
    }

    private func showTree(_ requested: Int?) throws {
        guard let input = session.lastInput, !session.lastTrees.isEmpty else { throw Message("No successful parse is available.") }
        let index = (requested ?? 1) - 1
        guard session.lastTrees.indices.contains(index) else { throw Message("Tree index must be between 1 and \(session.lastTrees.count).") }
        output(renderTree(session.lastTrees[index], in: input))
    }

    private func compareInput(_ requested: String?) throws {
        let input = requested ?? session.lastInput
        guard let input else {
            throw Message("Provide input after :compare or parse input first.")
        }
        let comparison = REPLParserExperiment.compare(
            grammar: try grammar(), input: input,
            precedence: session.precedence, resolutionPolicy: session.resolutionPolicy
        )
        session.storeComparison(comparison)
        for run in comparison.runs {
            let forest = run.contract.forest
            let forestSummary = forest.map {
                let ambiguity = $0.isAmbiguous ? "yes" : "no"
                return "nodes=\($0.nodes.count), ambiguous=\(ambiguity)"
            } ?? "forest=none"
            output("\(run.parser.rawValue): \(run.contract.status.rawValue), trees=\(run.trees.count), \(forestSummary), replay=\(run.contract.replay.count)")
            if let reason = run.unsupportedReason { output("  unsupported: \(reason)") }
            else if let failure = run.failure { output("  \(failure)") }
        }
        output("Agreement: \(comparison.agreement.rawValue).")
        if let mapping = session.semanticMapping {
            let report = semanticReport(comparison, mapping: mapping)
            output("Semantic agreement: \(report.agreement.rawValue).")
            for observation in report.observations where observation.status == .evaluated {
                output("  \(observation.engine): \(observation.values.map(\.displayValue).joined(separator: " | "))")
            }
        }
    }

    private func experimentRun(for requested: REPLParser?) throws -> REPLParserRun {
        guard let comparison = session.lastComparison else {
            throw Message("No engine comparison is available. Use :compare <input> first.")
        }
        let parser = requested ?? session.parser
        guard let run = comparison.run(for: parser) else {
            throw Message("No comparison result is available for \(parser.rawValue).")
        }
        return run
    }

    private func showForest(_ requested: REPLParser?) throws {
        let run = try experimentRun(for: requested)
        guard let forest = run.contract.forest else {
            throw Message("\(run.parser.rawValue) did not produce a packed forest.")
        }
        output("\(run.parser.rawValue) forest: \(forest.nodes.count) nodes, \(forest.edges.count) edges, \(forest.roots.count) root(s), \(forest.ambiguityNodes.count) ambiguity node(s).")
        for node in forest.nodes.prefix(50) {
            let ambiguous = forest.ambiguityNodes.contains(node.id) ? " [ambiguous]" : ""
            let label = node.productionID?.rawValue ?? node.label ?? ""
            let position = node.position.map { " @\($0)" } ?? ""
            let suffix = label.isEmpty ? "" : "  \(label)"
            output("\(node.id)  \(node.kind.rawValue) [\(node.leftExtent), \(node.rightExtent))\(position)\(ambiguous)\(suffix)")
        }
        if forest.nodes.count > 50 { output("… \(forest.nodes.count - 50) more node(s).") }
    }

    private func showPlayback(_ requested: REPLParser?, limit: Int?) throws {
        let run = try experimentRun(for: requested)
        let events = limit.map { Array(run.contract.replay.prefix(max(0, $0))) } ?? run.contract.replay
        guard !events.isEmpty else { throw Message("No portable replay is available for \(run.parser.rawValue).") }
        output("\(run.parser.rawValue) replay\(limit.map { " (first \($0))" } ?? ""):")
        for event in events {
            var details: [String] = []
            if let token = event.tokenIndex { details.append("token=\(token)") }
            if let production = event.productionID { details.append("production=\(production.rawValue)") }
            if let node = event.forestNodeID { details.append("node=\(node)") }
            if let reason = event.diagnosticReason { details.append("reason=\(reason.rawValue)") }
            let suffix = details.isEmpty ? "" : "  \(details.joined(separator: ", "))"
            output("[\(event.step)] \(event.kind.rawValue)\(suffix)")
        }
    }

    private func showContract(_ requested: REPLParser?) throws {
        let run = try experimentRun(for: requested)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        output(String(decoding: try encoder.encode(run.contract), as: UTF8.self))
    }

    private func saveExperiment(to path: String) throws {
        guard let loaded = session.loaded, let comparison = session.lastComparison else {
            throw Message("Load a grammar and use :compare <input> before saving an experiment.")
        }
        let document = try REPLExperimentDocument.capture(
            grammar: loaded.grammar, comparison: comparison,
            precedence: session.precedence, resolutionPolicy: session.resolutionPolicy,
            semanticMapping: session.semanticMapping
        )
        let url = URL(fileURLWithPath: path).standardizedFileURL
        try document.json().write(to: url, options: .atomic)
        output("Saved experiment \(document.fingerprint) to \(url.path).")
    }

    private func verifyExperiment(at path: String) throws {
        let document = try loadExperiment(at: path)
        let verification = try document.verify()
        for engine in verification.engines where !engine.matches {
            output("\(engine.parser.rawValue): changed \(engine.differences.map(\.rawValue).joined(separator: ", ")).")
        }
        if verification.matches {
            output("Experiment verified: \(verification.artifactFingerprint) (\(verification.engines.count) engines).")
        } else {
            if !verification.semanticMatches {
                throw Message("Experiment diverged: Compiler semantic evidence changed.")
            }
            throw Message("Experiment diverged: expected \(verification.expectedAgreement.rawValue), observed \(verification.actualAgreement.rawValue).")
        }
    }

    private func showExperiment(at path: String) throws {
        let document = try loadExperiment(at: path)
        output("Experiment \(document.fingerprint): schema \(document.schemaVersion), producer \(document.producer.name) \(document.producer.version).")
        output("Input: \(document.input.debugDescription)")
        output("Engines: \(document.engines.map(\.rawValue).joined(separator: ", ")).")
        output("Expected agreement: \(document.agreement.rawValue).")
        if let semantics = document.semanticReport {
            output("Expected semantic agreement: \(semantics.agreement.rawValue).")
        }
    }

    private func configureSemantics(_ path: String?) throws {
        guard let path else {
            output(session.semanticMapping == nil
                   ? "Compiler semantics: disabled."
                   : "Compiler semantics: enabled (\(session.semanticMapping!.actions.count) AST actions).")
            return
        }
        if path.lowercased() == "clear" {
            session.setSemanticMapping(nil)
            output("Compiler semantics disabled.")
            return
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        session.setSemanticMapping(try ASTMapping(json: Data(contentsOf: url)))
        output("Loaded Compiler semantic mapping from \(url.path).")
    }

    private func semanticReport(
        _ comparison: REPLParserComparison,
        mapping: ASTMapping
    ) -> CompilerSemanticConvergenceReport {
        CompilerSemanticConvergence.evaluate(
            source: comparison.input,
            inputs: comparison.runs.map {
                CompilerSemanticEngineInput(
                    engine: $0.parser.rawValue,
                    parseStatus: $0.contract.status,
                    trees: $0.trees
                )
            },
            mapping: mapping
        )
    }

    private func loadExperiment(at path: String) throws -> REPLExperimentDocument {
        try REPLExperimentDocument.decode(Data(contentsOf: URL(fileURLWithPath: path)))
    }

    private func showSettings() {
        output("Grammar: \(session.loaded?.url.path ?? "none")\nParser: \(session.parser.rawValue)\nLast input: \(session.lastInput ?? "none")\nComparison: \(session.lastComparison?.agreement.rawValue ?? "none")\nLR artifact: \(session.automaton.map { "\($0.states.count) states" } ?? "not generated")\nPrecedence levels: \(session.precedenceLevels.count)\nResolution policy: \(session.resolutionPolicy?.rawValue ?? "none")\nTracing: \(session.traceEnabled ? "on" : "off")")
    }

    private func showTrace(_ rawArgument: String?) {
        switch rawArgument?.lowercased() {
        case "on": session.setTraceEnabled(true); output("LR parser tracing enabled.")
        case "off": session.setTraceEnabled(false); output("LR parser tracing disabled.")
        case "clear": session.clearTrace(); output("Parser trace cleared.")
        case let value?:
            guard let limit = Int(value), limit > 0 else { output("Use :trace [on|off|clear|count]."); return }
            renderTrace(Array(session.lastTrace.suffix(limit)))
        case nil: renderTrace(session.lastTrace)
        }
    }

    private func renderTrace(_ events: [LRParserTraceEvent]) {
        guard !events.isEmpty else { output("No LR parser trace is available. Enable tracing and parse input first."); return }
        for event in events { output(event.description) }
    }

    private func showIdentity(_ rawSpecification: String) throws {
        let words = rawSpecification.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count == 2, let index = Int(words[1]) else { throw Message("Use :identity state|conflict|production <number>.") }
        let artifact = try automaton()
        switch words[0].lowercased() {
        case "state":
            guard let value = artifact.state(index) else { throw Message("Unknown LR state \(index).") }
            output(value.identity.rawValue)
        case "conflict":
            guard index > 0, artifact.allConflicts.indices.contains(index - 1) else { throw Message("Unknown one-based conflict \(index).") }
            output(artifact.allConflicts[index - 1].identity.rawValue)
        case "production":
            guard index > 0, artifact.productions.indices.contains(index - 1) else { throw Message("Unknown one-based production \(index).") }
            let value = artifact.productions[index - 1]
            output("\(value.identity.rawValue)\n\(value.production)")
        default: throw Message("Use :identity state|conflict|production <number>.")
        }
    }

    private func configurePrecedence(_ specification: String) throws {
        let words = specification.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.isEmpty {
            guard !session.precedenceLevels.isEmpty else { output("No precedence levels declared."); return }
            for level in session.precedenceLevels {
                output("\(level.precedence.level) \(level.precedence.associativity): \(level.terminals.map(\.description).sorted().joined(separator: ", "))")
            }
            return
        }
        if words.count == 1, words[0].lowercased() == "clear" {
            session.clearPrecedence()
            output("Precedence declarations cleared.")
            return
        }
        guard words.count >= 3, let number = Int(words[0]) else {
            throw Message("Use :precedence <level> <left|right|nonassoc> <terminal>... or :precedence clear.")
        }
        let associativity: LRAssociativity
        switch words[1].lowercased() {
        case "left": associativity = .left
        case "right": associativity = .right
        case "nonassoc", "none": associativity = .nonAssociative
        default: throw Message("Associativity must be left, right, or nonassoc.")
        }
        let available = try grammar().terminals
        let terminals = try Set(words.dropFirst(2).map { raw -> Terminal in
            let name = raw.count >= 2 && raw.first == "\"" && raw.last == "\"" ? String(raw.dropFirst().dropLast()) : raw
            let terminal = Terminal(string: name)
            guard available.contains(terminal) else { throw Message("Unknown string terminal \(raw).") }
            return terminal
        })
        session.setPrecedence(LRPrecedenceLevel(number, associativity: associativity, terminals: terminals))
        output("Declared precedence level \(number) as \(associativity) for \(terminals.map(\.description).sorted().joined(separator: ", ")).")
    }

    private func configureResolution(_ specification: String) throws {
        switch specification.lowercased() {
        case "": output("Resolution policy: \(session.resolutionPolicy?.rawValue ?? "none").")
        case "shift": session.setResolutionPolicy(.preferShift); output("Resolution policy set to prefer shift.")
        case "reduce": session.setResolutionPolicy(.preferReduce); output("Resolution policy set to prefer reduce.")
        case "reject": session.setResolutionPolicy(.reject); output("Resolution policy set to reject conflicted cells.")
        case "clear", "none": session.setResolutionPolicy(nil); output("Resolution policy cleared.")
        default: throw Message("Use :resolution [shift|reduce|reject|clear].")
        }
    }

    private func renderArtifact(_ rawSpecification: String) throws -> RenderedArtifact {
        let words = rawSpecification.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let kind = words.first?.lowercased() else {
            throw Message("Use :diagram grammar|rule <name>|automaton|state <number>|conflict <number>|tree")
        }
        switch kind {
        case "grammar": return try RailroadGrammarRenderer().render(grammar())
        case "rule":
            guard words.count == 2 else { throw Message("Use :diagram rule <name>") }
            return try RailroadGrammarRenderer().render(rule: words[1], in: grammar())
        case "automaton": return try LRAutomatonDOTRenderer().render(automaton())
        case "state":
            guard words.count == 2, let id = Int(words[1]) else { throw Message("Use :diagram state <number>") }
            return try LRAutomatonDOTRenderer(selectedState: id).render(automaton())
        case "conflict":
            guard words.count == 2, let index = Int(words[1]), index > 0 else { throw Message("Use :diagram conflict <number>") }
            let artifact = try automaton()
            guard artifact.allConflicts.indices.contains(index - 1) else { throw Message("Unknown one-based conflict \(index).") }
            return try LRConflictDOTRenderer().render(artifact.allConflicts[index - 1], in: artifact)
        case "tree":
            guard let tree = session.lastTrees.first, let source = session.lastInput else { throw ArtifactRenderingError.unavailable("No successful parse tree is available.") }
            return try SyntaxTreeDOTRenderer().render((tree, source))
        default:
            // Compact export spelling: rule:name or state:number.
            if kind.hasPrefix("rule:") { return try RailroadGrammarRenderer().render(rule: String(kind.dropFirst(5)), in: grammar()) }
            if kind.hasPrefix("state:"), let id = Int(kind.dropFirst(6)) { return try LRAutomatonDOTRenderer(selectedState: id).render(automaton()) }
            if kind.hasPrefix("conflict:"), let index = Int(kind.dropFirst(9)), index > 0 {
                let artifact = try automaton()
                guard artifact.allConflicts.indices.contains(index - 1) else { throw Message("Unknown one-based conflict \(index).") }
                return try LRConflictDOTRenderer().render(artifact.allConflicts[index - 1], in: artifact)
            }
            throw Message("Unknown graphical artifact: \(kind)")
        }
    }

    private func exportArtifact(_ specification: String, to path: String) throws {
        let artifact = try renderArtifact(specification)
        let url = URL(fileURLWithPath: path).standardizedFileURL
        try artifact.content.write(to: url, atomically: true, encoding: .utf8)
        output("Exported \(artifact.format.rawValue) to \(url.path).")
    }

    private func grammar() throws -> Grammar {
        guard let value = session.loaded?.grammar else { throw Message("No grammar is loaded. Use :load <file> [start].") }
        return value
    }

    private func automaton() throws -> LR_Parsing.LRAutomaton {
        if let value = session.automaton { return value }
        guard let algorithm = session.parser.lrAlgorithm else { throw Message("Select lr0, slr, lalr, or lr1 first.") }
        let value = LRParser(grammar: try grammar(), algorithm: algorithm, precedence: session.precedence, resolutionPolicy: session.resolutionPolicy).generate()
        session.storeAutomaton(value)
        return value
    }

    private func findNonterminal(_ raw: String) throws -> NonTerminal {
        let name = raw.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        guard let value = try grammar().nonTerminals.first(where: { $0.name == name }) else { throw Message("Unknown nonterminal <\(name)>.") }
        return value
    }

    private func render(_ symbols: Set<Symbol>) -> String { symbols.map(\.description).sorted().joined(separator: ", ") }

    private func render(_ action: LR_Parsing.LRAction) -> String {
        switch action {
        case .shift(let target): "shift to state \(target)"
        case .reduce(let production): "reduce by \(production)"
        case .accept: "accept"
        }
    }

    private func renderTree(_ tree: ParseTree, in source: String) -> String {
        func visit(_ node: ParseTree, prefix: String, marker: String) -> [String] {
            switch node {
            case .empty: return [prefix + marker + "ε"]
            case .leaf(let range): return [prefix + marker + String(source[range]).debugDescription]
            case .node(let nt, let children):
                var lines = [prefix + marker + nt.name]
                for (index, child) in children.enumerated() {
                    lines += visit(child, prefix: prefix + (marker.isEmpty ? "" : "    "), marker: index == children.count - 1 ? "└── " : "├── ")
                }
                return lines
            }
        }
        return visit(tree, prefix: "", marker: "").joined(separator: "\n")
    }

    private static let help = """
    Commands:
      :load <file> [start]   Load a grammar
      :parser [name]         Select earley/earley-sl/earley-el/cyk/rnglr/ll1/lr0/slr/lalr/lr1
      :check                 Show LL and selected LR analysis summary
      :conflicts             List structured LL or LR conflicts
      :decisions [state]     Inspect generated ACTION decisions
      :state <number>        Inspect an LR state and outgoing transitions
      :explain <number>      Explain an LR conflict with shortest witness
      :replay <number> [all] Replay a witness, optionally forcing all branches
      :precedence <spec>     List/set/clear LR precedence declarations
      :resolution [policy]  Set shift/reduce/reject conflict policy
      :first/:follow/:predict <nonterminal>
      :parse <input>         Parse; LR modes use bounded local repair
      :tree [number]         Show the last parse tree
      :compare [input]       Run every parser against the same input
      :forest [parser]       Explore a compared parser's portable forest
      :playback [parser] [n] Replay portable semantic parse events
      :contract [parser]     Print a parser's portable contract as JSON
      :experiment <op> <file> Save, show, or verify a reproducible experiment
      :semantics [file|clear] Load/show/clear a Compiler AST mapping
      :trace [option]        Enable/disable/show/clear LR runtime tracing
      :identity <kind> <n>   Show a stable state/conflict/production ID
      :diagram <artifact>    Render grammar/rule/automaton/state/tree
      :export <kind> <path>  Export (use rule:name or state:number)
      :history               Show this session's command history
      :reload / :grammar / :settings / :help / :quit
    """
}

private struct Message: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
