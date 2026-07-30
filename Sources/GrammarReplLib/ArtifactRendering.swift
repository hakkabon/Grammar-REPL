//
//  ArtifactRendering.swift
//  Grammar-REPL
//
//  Created by Ulf Akerstedt-Inoue on 2026/07/66.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import GrammarDiagram
import Parser
import LR_Parsing

public enum ArtifactFormat: String { case text, dot }

public struct RenderedArtifact {
    public let format: ArtifactFormat
    public let content: String
    public let suggestedExtension: String

    public init(format: ArtifactFormat, content: String, suggestedExtension: String) {
        self.format = format
        self.content = content
        self.suggestedExtension = suggestedExtension
    }
}

public protocol GrammarArtifactRenderer {
    associatedtype Artifact
    func render(_ artifact: Artifact) throws -> RenderedArtifact
}

public struct RailroadGrammarRenderer: GrammarArtifactRenderer {
    public init() {}
    public func render(_ grammar: Grammar) throws -> RenderedArtifact {
        RenderedArtifact(format: .text, content: GrammarToRailroad().generateDiagrams(grammar.syntaxTree), suggestedExtension: "txt")
    }

    public func render(rule name: String, in grammar: Grammar) throws -> RenderedArtifact {
        guard let content = GrammarToRailroad().generateDiagram(forProduction: name, in: grammar.syntaxTree) else {
            throw ArtifactRenderingError.unknownRule(name)
        }
        return RenderedArtifact(format: .text, content: content, suggestedExtension: "txt")
    }
}

public struct LRAutomatonDOTRenderer: GrammarArtifactRenderer {
    public let selectedState: Int?
    public init(selectedState: Int? = nil) { self.selectedState = selectedState }

    public func render(_ automaton: LR_Parsing.LRAutomaton) throws -> RenderedArtifact {
        if let selectedState, automaton.state(selectedState) == nil { throw ArtifactRenderingError.unknownState(selectedState) }
        let states = selectedState.map { Set([$0]) } ?? Set(automaton.states.map(\.id))
        var lines = ["digraph LRAutomaton {", "  rankdir=LR;", "  node [shape=box,fontname=\"Menlo\"];"]
        for state in automaton.states where states.contains(state.id) {
            let items = state.items.map(\.description).sorted().joined(separator: "\\l") + "\\l"
            let conflict = automaton.conflicts.contains { $0.state == state.id }
            lines.append("  s\(state.id) [label=\"State \(state.id)\\l\(escape(items))\"\(conflict ? ",color=red,penwidth=2" : "")];")
        }
        for edge in automaton.transitions where selectedState == nil || edge.source == selectedState {
            if selectedState != nil && !states.contains(edge.target) {
                lines.append("  s\(edge.target) [label=\"State \(edge.target)\"];")
            }
            lines.append("  s\(edge.source) -> s\(edge.target) [label=\"\(escape(edge.symbol.description))\"];")
        }
        lines.append("}")
        return RenderedArtifact(format: .dot, content: lines.joined(separator: "\n"), suggestedExtension: "dot")
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\l")
    }
}

/// Conflict-focused Graphviz renderer combining the automaton witness path,
/// competing action origins, selected decision, and forced branch outcomes.
public struct LRConflictDOTRenderer {
    public init() {}

    public func render(_ conflict: LRConflict, in automaton: LR_Parsing.LRAutomaton) throws -> RenderedArtifact {
        guard automaton.conflict(identity: conflict.identity) != nil else { throw ArtifactRenderingError.unknownConflict(conflict.identity.rawValue) }
        let replay = automaton.replay(conflict)
        let witnessStates = Set(replay.steps.map { $0.state.index })
        let witnessEdges = Set(zip(replay.steps, replay.steps.dropFirst()).map { left, right in "\(left.state.index)->\(right.state.index)" })
        let conflictColor = conflict.isResolved ? "#d97706" : "#dc2626"
        let conflictFill = conflict.isResolved ? "#ffedd5" : "#fee2e2"
        let graphLabel = "\(conflict.kind.rawValue) on \(conflict.lookahead.description)\nWitness: \(conflict.witness.map(\.description).joined(separator: " "))"
        var lines = [
            "digraph LRConflictExplanation {",
            "  rankdir=LR;",
            "  graph [labelloc=\"t\",label=\"\(escape(graphLabel))\"] ;",
            "  node [fontname=\"Menlo\"] ;"
        ]

        lines.append("  subgraph cluster_automaton {")
        lines.append("    label=\"Automaton and witness path\";")
        for state in automaton.states {
            var attributes = ["shape=box", "label=\"State \(state.id)\""]
            if state.id == conflict.state {
                attributes += ["color=\"\(conflictColor)\"", "penwidth=3", "style=filled", "fillcolor=\"\(conflictFill)\""]
            } else if witnessStates.contains(state.id) {
                attributes += ["color=\"#ca8a04\"", "penwidth=2", "style=filled", "fillcolor=\"#fef9c3\""]
            }
            lines.append("    s\(state.id) [\(attributes.joined(separator: ","))];")
        }
        for edge in automaton.transitions {
            let highlighted = witnessEdges.contains("\(edge.source)->\(edge.target)")
            let style = highlighted ? ",color=\"#ca8a04\",penwidth=3" : ",color=\"#9ca3af\""
            lines.append("    s\(edge.source) -> s\(edge.target) [label=\"\(escape(edge.symbol.description))\"\(style)];")
        }
        lines.append("  }")

        lines.append("  subgraph cluster_actions {")
        lines.append("    label=\"Competing action origins\";")
        for (index, candidate) in conflict.candidates.enumerated() {
            let selected = conflict.decision?.selectedAction == candidate.action
            let fill = selected ? "#dcfce7" : "#f3f4f6"
            let color = selected ? "#16a34a" : "#6b7280"
            let status = selected ? "selected" : "not selected"
            let label = "\(actionDescription(candidate.action)) [\(status)]\n\(candidate.reason)\n\(candidate.item)\nItem ID: \(candidate.item.identity)\nCandidate ID: \(candidate.identity)"
            lines.append("    a\(index) [shape=ellipse,style=filled,fillcolor=\"\(fill)\",color=\"\(color)\",label=\"\(escape(label))\"];")
            lines.append("    s\(conflict.state) -> a\(index) [style=dashed,color=\"\(color)\"];")
        }
        lines.append("  }")

        if let decision = conflict.decision {
            let action = decision.selectedAction.map(actionDescription) ?? "error ACTION"
            let label = "Decision [\(decision.status.rawValue)]\n\(action)\n\(decision.resolution)\nDecision ID: \(decision.identity)"
            lines.append("  decision [shape=note,style=filled,fillcolor=\"#dbeafe\",color=\"#2563eb\",label=\"\(escape(label))\"];")
            lines.append("  s\(conflict.state) -> decision [color=\"#2563eb\",penwidth=2];")
        }

        for (index, branch) in automaton.replayBranches(conflict).enumerated() {
            let label = "Force \(actionDescription(branch.action))\(branch.wasSelected ? " [selected]" : "")\nBranch outcome: \(branch.outcome)"
            lines.append("  b\(index) [shape=component,label=\"\(escape(label))\"];")
            lines.append("  s\(conflict.state) -> b\(index) [style=dotted];")
        }
        lines.append("}")
        return RenderedArtifact(format: .dot, content: lines.joined(separator: "\n"), suggestedExtension: "dot")
    }

    private func actionDescription(_ action: LR_Parsing.LRAction) -> String {
        switch action {
        case .shift(let state): "shift to state \(state)"
        case .reduce(let production): "reduce by \(production)"
        case .accept: "accept"
        }
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
    }
}

public struct SyntaxTreeDOTRenderer: GrammarArtifactRenderer {
    public init() {}
    public func render(_ artifact: (tree: ParseTree, source: String)) throws -> RenderedArtifact {
        let dot = artifact.tree.mapNodes(\.name).mapLeafs { String(artifact.source[$0]) }.graphviz
        return RenderedArtifact(format: .dot, content: dot, suggestedExtension: "dot")
    }
}

public enum ArtifactRenderingError: Error, CustomStringConvertible {
    case unknownRule(String), unknownState(Int), unknownConflict(String), unavailable(String)
    public var description: String {
        switch self {
        case .unknownRule(let name): "Unknown grammar rule <\(name)>."
        case .unknownState(let id): "Unknown LR state \(id)."
        case .unknownConflict(let id): "Unknown LR conflict \(id)."
        case .unavailable(let message): message
        }
    }
}
