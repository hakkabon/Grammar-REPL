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

public struct SyntaxTreeDOTRenderer: GrammarArtifactRenderer {
    public init() {}
    public func render(_ artifact: (tree: ParseTree, source: String)) throws -> RenderedArtifact {
        let dot = artifact.tree.mapNodes(\.name).mapLeafs { String(artifact.source[$0]) }.graphviz
        return RenderedArtifact(format: .dot, content: dot, suggestedExtension: "dot")
    }
}

public enum ArtifactRenderingError: Error, CustomStringConvertible {
    case unknownRule(String), unknownState(Int), unavailable(String)
    public var description: String {
        switch self {
        case .unknownRule(let name): "Unknown grammar rule <\(name)>."
        case .unknownState(let id): "Unknown LR state \(id)."
        case .unavailable(let message): message
        }
    }
}
