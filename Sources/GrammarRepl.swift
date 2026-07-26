//
//  GrammarRepl.swift
//  Grammar-REPL
//
//  Created by Ulf Akerstedt-Inoue on 2026/07/25.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import Parser
import RNGLR_Parser
import CYK_Parser
import Earley_Parser

enum REPLParser: String, CaseIterable {
    case earley, cyk, rnglr
}

enum REPLNotation: String, CaseIterable {
    case bnf, ebnf, wsn, gen
}

struct LoadedGrammar {
    let url: URL
    let notation: REPLNotation
    let start: String?
    let grammar: Grammar
}

struct REPLSession {
    var loaded: LoadedGrammar?
    var parser: REPLParser = .earley
    var lastInput: String?
    var lastTrees: [ParseTree] = []
}

enum REPLCommand: Equatable {
    case help
    case quit
    case load(path: String, start: String?)
    case reload
    case grammar
    case parser(REPLParser?)
    case check
    case first(String)
    case follow(String)
    case predict(String)
    case parse(String)
    case tree(Int?)
    case settings
    case unknown(String)

    static func decode(_ line: String) -> REPLCommand {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .unknown("") }
        guard text.first == ":" else { return .parse(text) }

        let body = text.dropFirst()
        let split = body.firstIndex(where: { $0.isWhitespace })
        let name = String(split.map { body[..<$0] } ?? body[...]).lowercased()
        let argument = split.map { String(body[$0...]).trimmingCharacters(in: .whitespaces) } ?? ""

        switch name {
        case "help", "?": return .help
        case "quit", "exit", "q": return .quit
        case "load":
            let words = shellWords(argument)
            return words.isEmpty ? .unknown(text) : .load(path: words[0], start: words.count > 1 ? words[1] : nil)
        case "reload": return .reload
        case "grammar": return .grammar
        case "parser": return .parser(REPLParser(rawValue: argument.lowercased()))
        case "check": return .check
        case "first": return .first(argument)
        case "follow": return .follow(argument)
        case "predict": return .predict(argument)
        case "parse": return .parse(unquote(argument))
        case "tree": return .tree(argument.isEmpty ? nil : Int(argument))
        case "settings": return .settings
        default: return .unknown(text)
        }
    }

    private static func unquote(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, first == text.last, first == "\"" || first == "'" else { return text }
        return String(text.dropFirst().dropLast())
    }

    private static func shellWords(_ text: String) -> [String] {
        var result: [String] = [], word = ""
        var quote: Character?
        for character in text {
            if let active = quote {
                if character == active { quote = nil } else { word.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !word.isEmpty { result.append(word); word = "" }
            } else {
                word.append(character)
            }
        }
        if !word.isEmpty { result.append(word) }
        return result
    }
}

final class GrammarREPL {
    private(set) var session = REPLSession()
    private let output: (String) -> Void

    init(output: @escaping (String) -> Void = { print($0) }) {
        self.output = output
    }

    func run() {
        output("Grammar REPL — type :help for commands")
        while true {
            Swift.print("grammar> ", terminator: "")
            guard let line = readLine() else { break }
            if !execute(.decode(line)) { break }
        }
    }

    @discardableResult
    func execute(_ command: REPLCommand) -> Bool {
        do {
            switch command {
            case .help: output(Self.help)
            case .quit: return false
            case .load(let path, let start): try load(path: path, start: start)
            case .reload: try reload()
            case .grammar: try showGrammar()
            case .parser(let parser): setParser(parser)
            case .check: try check()
            case .first(let name): try showFirst(name)
            case .follow(let name): try showFollow(name)
            case .predict(let name): try showPredict(name)
            case .parse(let input): try parseInput(input)
            case .tree(let index): try showTree(index)
            case .settings: showSettings()
            case .unknown(let text):
                if !text.isEmpty { output("Unknown or incomplete command: \(text)\nType :help for usage.") }
            }
        } catch {
            output("Error: \(error)")
        }
        return true
    }

    private func load(path: String, start: String?) throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let notation = REPLNotation(rawValue: url.pathExtension.lowercased()) ?? .gen
        let text = try String(contentsOf: url, encoding: .utf8)
        let grammar = try makeGrammar(text, notation: notation, start: start)
        session.loaded = LoadedGrammar(url: url, notation: notation, start: start, grammar: grammar)
        session.lastInput = nil
        session.lastTrees = []
        output("Loaded \(url.lastPathComponent): \(grammar.productions.count) productions, start <\(grammar.start.name)>.")
    }

    private func reload() throws {
        guard let loaded = session.loaded else { throw Message("No grammar is loaded.") }
        try load(path: loaded.url.path, start: loaded.start)
    }

    private func makeGrammar(_ text: String, notation: REPLNotation, start: String?) throws -> Grammar {
        switch notation {
        case .gen: return try Grammar(gen: text)
        case .bnf:
            guard let start, !start.isEmpty else { throw Message("BNF requires a start rule: :load file.bnf start") }
            return try Grammar(bnf: text, start: start)
        case .ebnf:
            guard let start, !start.isEmpty else { throw Message("EBNF requires a start rule: :load file.ebnf start") }
            return try Grammar(ebnf: text, start: start)
        case .wsn:
            guard let start, !start.isEmpty else { throw Message("WSN requires a start rule: :load file.wsn start") }
            return try Grammar(wsn: text, start: start)
        }
    }

    private func showGrammar() throws {
        output(String(describing: try grammar()))
    }

    private func setParser(_ parser: REPLParser?) {
        guard let parser else {
            output("Parser: \(session.parser.rawValue). Available: \(REPLParser.allCases.map(\.rawValue).joined(separator: ", ")).")
            return
        }
        session.parser = parser
        session.lastTrees = []
        output("Parser set to \(parser.rawValue).")
    }

    private func check() throws {
        let grammar = try grammar()
        let conflicts = llConflicts(in: grammar)
        output("Grammar: \(grammar.productions.count) productions, \(grammar.nonTerminals.count) nonterminals, \(grammar.terminals.count) terminals.")
        if conflicts.isEmpty {
            output("LL(1) prediction sets are disjoint.")
        } else {
            output("Found \(conflicts.count) LL(1) prediction conflict\(conflicts.count == 1 ? "" : "s"):")
            for (offset, conflict) in conflicts.enumerated() {
                output("[\(offset + 1)] <\(conflict.nonterminal.name)> on {\(render(conflict.lookaheads))}\n    \(conflict.first)\n    \(conflict.second)")
            }
        }
        output("Selected runtime parser: \(session.parser.rawValue).")
    }

    private func showFirst(_ name: String) throws {
        let grammar = try grammar()
        let nonterminal = try findNonterminal(name, in: grammar)
        let (first, _) = grammar.firstAndFollow()
        output("FIRST(<\(nonterminal.name)>) = {\(render(first[.nonTerminal(nonterminal)] ?? []))}")
    }

    private func showFollow(_ name: String) throws {
        let grammar = try grammar()
        let nonterminal = try findNonterminal(name, in: grammar)
        let (_, follow) = grammar.firstAndFollow()
        output("FOLLOW(<\(nonterminal.name)>) = {\(render(follow[nonterminal] ?? []))}")
    }

    private func showPredict(_ name: String) throws {
        let grammar = try grammar()
        let nonterminal = try findNonterminal(name, in: grammar)
        let (first, follow) = grammar.firstAndFollow()
        let productions = grammar.productions.filter { $0.goal == nonterminal }
        guard !productions.isEmpty else { throw Message("No productions found for <\(name)>.") }
        for (index, production) in productions.enumerated() {
            output("[\(index + 1)] \(production)\n    PREDICT = {\(render(predict(production, first: first, follow: follow, grammar: grammar)))}")
        }
    }

    private func parseInput(_ input: String) throws {
        guard !input.isEmpty else { throw Message("Provide input after :parse, or enter it directly at the prompt.") }
        let grammar = try grammar()
        let trees: [ParseTree]
        switch session.parser {
        case .earley: trees = try EarleyParser(grammar: grammar).allSyntaxTrees(for: input)
        case .cyk: trees = try CYKParser(grammar: grammar).allSyntaxTrees(for: input)
        case .rnglr: trees = try RNGLRParser(grammar: grammar).allSyntaxTrees(for: input)
        }
        session.lastInput = input
        session.lastTrees = trees
        output("Accepted by \(session.parser.rawValue): \(trees.count) derivation\(trees.count == 1 ? "" : "s").")
    }

    private func showTree(_ requested: Int?) throws {
        guard !session.lastTrees.isEmpty else { throw Message("No successful parse is available. Use :parse first.") }
        guard let input = session.lastInput else { throw Message("The source text for the last parse is unavailable.") }
        let index = (requested ?? 1) - 1
        guard session.lastTrees.indices.contains(index) else { throw Message("Tree index must be between 1 and \(session.lastTrees.count).") }
        output(renderTree(session.lastTrees[index], in: input))
    }

    private func showSettings() {
        output("Grammar: \(session.loaded?.url.path ?? "none")\nParser: \(session.parser.rawValue)\nLast input: \(session.lastInput ?? "none")")
    }

    private func grammar() throws -> Grammar {
        guard let loaded = session.loaded else { throw Message("No grammar is loaded. Use :load <file> [start].") }
        return loaded.grammar
    }

    private func findNonterminal(_ rawName: String, in grammar: Grammar) throws -> NonTerminal {
        let name = rawName.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        guard let result = grammar.nonTerminals.first(where: { $0.name == name }) else { throw Message("Unknown nonterminal <\(name)>.") }
        return result
    }

    private struct LLConflict {
        let nonterminal: NonTerminal
        let first: Production
        let second: Production
        let lookaheads: Set<Symbol>
    }

    private func llConflicts(in grammar: Grammar) -> [LLConflict] {
        let (first, follow) = grammar.firstAndFollow()
        var result: [LLConflict] = []
        for nonterminal in grammar.nonTerminals.sorted() {
            let productions = grammar.productions.filter { $0.goal == nonterminal }
            for left in productions.indices {
                for right in productions.indices where right > left {
                    let overlap = predict(productions[left], first: first, follow: follow, grammar: grammar)
                        .intersection(predict(productions[right], first: first, follow: follow, grammar: grammar))
                    if !overlap.isEmpty {
                        result.append(LLConflict(nonterminal: nonterminal, first: productions[left], second: productions[right], lookaheads: overlap))
                    }
                }
            }
        }
        return result
    }

    private func predict(_ production: Production, first: [Symbol: Set<Symbol>], follow: [NonTerminal: Set<Symbol>], grammar: Grammar) -> Set<Symbol> {
        var result = grammar.first(of: production.rule, using: first)
        let epsilon = Symbol.terminal(.meta(grammar.epsilon))
        if result.remove(epsilon) != nil || production.rule.isEmpty {
            result.formUnion(follow[production.goal] ?? [])
        }
        return result
    }

    private func render(_ symbols: Set<Symbol>) -> String {
        symbols.map(\.description).sorted().joined(separator: ", ")
    }

    private func renderTree(_ tree: ParseTree, in source: String) -> String {
        func visit(_ node: ParseTree, prefix: String, marker: String) -> [String] {
            switch node {
            case .empty:
                return [prefix + marker + "ε"]
            case .leaf(let range):
                return [prefix + marker + String(source[range]).debugDescription]
            case .node(let nonterminal, let children):
                var lines = [prefix + marker + nonterminal.name]
                for (index, child) in children.enumerated() {
                    let last = index == children.count - 1
                    lines += visit(child, prefix: prefix + (marker.isEmpty ? "" : "    "), marker: last ? "└── " : "├── ")
                }
                return lines
            }
        }
        return visit(tree, prefix: "", marker: "").joined(separator: "\n")
    }

    private static let help = """
    Commands:
      :load <file> [start]   Load .gen/.bnf/.ebnf/.wsn grammar
      :reload                Reload the current grammar from disk
      :grammar               Show the normalized grammar
      :parser [name]         Show/select earley, cyk, or rnglr
      :check                 Show grammar summary and LL(1) conflicts
      :first <nonterminal>   Show a FIRST set
      :follow <nonterminal>  Show a FOLLOW set
      :predict <nonterminal> Show PREDICT sets for its alternatives
      :parse <input>         Parse input (:parse "quoted input" is accepted)
      :tree [number]         Show a tree from the last successful parse
      :settings              Show current session state
      :help                  Show this help
      :quit                  Exit

    A line without a leading colon is treated as sample input.
    """
}

private struct Message: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
