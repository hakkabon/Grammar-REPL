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
            case .conflicts: try showConflicts()
            case .state(let id): try showState(id)
            case .explain(let id): try explain(id)
            case .replay(let id): try replay(id)
            case .first(let name): try showFirst(name)
            case .follow(let name): try showFollow(name)
            case .predict(let name): try showPredict(name)
            case .parse(let input): try parseInput(input)
            case .tree(let index): try showTree(index)
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
        let value: Grammar
        switch notation {
        case .gen: value = try Grammar(gen: text)
        case .bnf:
            guard let start, !start.isEmpty else { throw Message("BNF requires a start rule: :load file.bnf start") }
            value = try Grammar(bnf: text, start: start)
        case .ebnf:
            guard let start, !start.isEmpty else { throw Message("EBNF requires a start rule: :load file.ebnf start") }
            value = try Grammar(ebnf: text, start: start)
        case .wsn:
            guard let start, !start.isEmpty else { throw Message("WSN requires a start rule: :load file.wsn start") }
            value = try Grammar(wsn: text, start: start)
        }
        session.load(LoadedGrammar(url: url, notation: notation, start: start, grammar: value))
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

    private func showConflicts() throws {
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
        let conflicts = try automaton().conflicts
        guard !conflicts.isEmpty else { output("No \(session.parser.rawValue.uppercased()) conflicts."); return }
        for (index, conflict) in conflicts.enumerated() {
            output("[\(index + 1)] [\(conflict.status.rawValue)] \(conflict)\n    witness: \(conflict.witness.map(\.description).joined(separator: " "))")
        }
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
        let conflicts = try automaton().conflicts
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

    private func replay(_ requested: Int?) throws {
        guard let requested, requested > 0 else { throw Message("Provide a one-based conflict number: :replay <number>") }
        let artifact = try automaton()
        guard artifact.conflicts.indices.contains(requested - 1) else { throw Message("Conflict number must be between 1 and \(artifact.conflicts.count).") }
        let conflict = artifact.conflicts[requested - 1]
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
        case .cyk: trees = try CYKParser(grammar: grammar).allSyntaxTrees(for: input)
        case .rnglr: trees = try RNGLRParser(grammar: grammar).allSyntaxTrees(for: input)
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

    private func showSettings() {
        output("Grammar: \(session.loaded?.url.path ?? "none")\nParser: \(session.parser.rawValue)\nLast input: \(session.lastInput ?? "none")\nLR artifact: \(session.automaton.map { "\($0.states.count) states" } ?? "not generated")\nPrecedence levels: \(session.precedenceLevels.count)\nResolution policy: \(session.resolutionPolicy?.rawValue ?? "none")\nTracing: \(session.traceEnabled ? "on" : "off")")
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
            guard index > 0, artifact.conflicts.indices.contains(index - 1) else { throw Message("Unknown one-based conflict \(index).") }
            output(artifact.conflicts[index - 1].identity.rawValue)
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
            throw Message("Use :diagram grammar|rule <name>|automaton|state <number>|tree")
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
        case "tree":
            guard let tree = session.lastTrees.first, let source = session.lastInput else { throw ArtifactRenderingError.unavailable("No successful parse tree is available.") }
            return try SyntaxTreeDOTRenderer().render((tree, source))
        default:
            // Compact export spelling: rule:name or state:number.
            if kind.hasPrefix("rule:") { return try RailroadGrammarRenderer().render(rule: String(kind.dropFirst(5)), in: grammar()) }
            if kind.hasPrefix("state:"), let id = Int(kind.dropFirst(6)) { return try LRAutomatonDOTRenderer(selectedState: id).render(automaton()) }
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
      :parser [name]         Select earley/cyk/rnglr/lr0/slr/lalr/lr1
      :check                 Show LL and selected LR analysis summary
      :conflicts             List structured LL or LR conflicts
      :state <number>        Inspect an LR state and outgoing transitions
      :explain <number>      Explain an LR conflict with shortest witness
      :replay <number>       Replay a witness to its LR conflict decision
      :precedence <spec>     List/set/clear LR precedence declarations
      :resolution [policy]  Set shift/reduce/reject conflict policy
      :first/:follow/:predict <nonterminal>
      :parse <input>         Parse; LR modes use bounded local repair
      :tree [number]         Show the last parse tree
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
