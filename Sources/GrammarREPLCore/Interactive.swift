import Foundation

/// Bounded, duplicate-collapsing command history independent of any terminal UI.
public struct CommandHistory {
    public let capacity: Int
    public private(set) var entries: [String] = []

    public init(capacity: Int = 500) { self.capacity = max(1, capacity) }

    public mutating func append(_ line: String) {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != entries.last else { return }
        entries.append(value)
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }
}

/// Semantic completion candidates. The terminal adapter is responsible only
/// for presenting these values; it does not duplicate command knowledge.
public enum CommandCompletion {
    public static let commands = [
        ":help", ":quit", ":load", ":reload", ":grammar", ":parser",
        ":check", ":conflicts", ":state", ":explain", ":first", ":follow",
        ":predict", ":parse", ":tree", ":diagram", ":export", ":history", ":settings"
    ]

    public static func candidates(for line: String, session: REPLSession) -> [String] {
        let prefix = line.trimmingCharacters(in: .whitespaces)
        let parts = prefix.split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.count <= 1 { return commands.filter { $0.hasPrefix(prefix) }.sorted() }
        let command = parts[0]
        let fragment = parts.last ?? ""
        let values: [String]
        switch command {
        case ":parser": values = REPLParser.allCases.map(\.rawValue)
        case ":first", ":follow", ":predict": values = session.loaded?.grammar.nonTerminals.map(\.name) ?? []
        case ":state": values = session.automaton?.states.map { String($0.id) } ?? []
        case ":explain": values = session.automaton?.conflicts.indices.map { String($0 + 1) } ?? []
        case ":diagram": values = ["grammar", "automaton", "tree", "rule", "state"]
        default: values = []
        }
        return values.filter { $0.hasPrefix(fragment) }.sorted()
    }
}
