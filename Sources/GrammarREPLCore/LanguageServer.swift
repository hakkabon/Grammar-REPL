import Foundation

/// Minimal Language Server Protocol-shaped façade. Transport framing remains
/// the host application's responsibility; these methods map directly to
/// textDocument/didOpen, didChange, didClose, completion, and definition.
public final class GrammarLanguageServer {
    public let workbench: GrammarWorkbenchService
    public init(workbench: GrammarWorkbenchService = .init()) { self.workbench = workbench }

    @discardableResult
    public func didOpen(uri: URL, text: String, version: Int, configuration: GrammarDocumentConfiguration) -> WorkbenchDocumentSnapshot {
        workbench.open(uri: uri, source: text, revision: version, configuration: configuration)
    }

    @discardableResult
    public func didChange(uri: URL, version: Int, changes: [GrammarTextDocumentChange]) throws -> WorkbenchDocumentSnapshot {
        var text = try workbench.snapshot(uri: uri).source
        for change in changes {
            if let range = change.range {
                let utf16Range = try Self.utf16Range(range, in: text)
                guard let swiftRange = Range(NSRange(location: utf16Range.location, length: utf16Range.length), in: text) else { throw WorkbenchServiceError.invalidEdit(utf16Range) }
                text.replaceSubrange(swiftRange, with: change.text)
            } else { text = change.text }
        }
        return try workbench.change(uri: uri, revision: version, replacement: text)
    }

    public func didClose(uri: URL) { workbench.close(uri: uri) }
    public func completion(uri: URL, prefix: String) throws -> [GrammarCompletionItem] {
        try workbench.completions(uri: uri, prefix: prefix).map { .init(label: $0, kind: "nonterminal") }
    }
    public func definition(uri: URL, nonterminal: String) throws -> WorkbenchLocation? { try workbench.definition(uri: uri, nonterminal: nonterminal) }
    public func artifact(uri: URL) throws -> WorkbenchArtifactEnvelope? { try workbench.snapshot(uri: uri).artifact }
    public func diagnostics(uri: URL) throws -> [WorkbenchDiagnostic] { try workbench.snapshot(uri: uri).diagnostics }

    private static func utf16Range(_ range: GrammarLSPRange, in source: String) throws -> WorkbenchSourceRange {
        let ns = source as NSString
        func offset(_ position: GrammarLSPPosition) -> Int? {
            var line = 0, cursor = 0
            while line < position.line {
                let found = ns.range(of: "\n", options: [], range: NSRange(location: cursor, length: ns.length - cursor))
                guard found.location != NSNotFound else { return nil }
                cursor = found.location + found.length; line += 1
            }
            let value = cursor + position.character
            return value <= ns.length ? value : nil
        }
        guard let start = offset(range.start), let end = offset(range.end), end >= start else { throw WorkbenchServiceError.invalidEdit(.init(location: 0, length: 0)) }
        return .init(location: start, length: end - start)
    }
}

public struct GrammarLSPPosition: Codable, Equatable, Sendable { public let line: Int; public let character: Int; public init(line: Int, character: Int) { self.line = line; self.character = character } }
public struct GrammarLSPRange: Codable, Equatable, Sendable { public let start: GrammarLSPPosition; public let end: GrammarLSPPosition; public init(start: GrammarLSPPosition, end: GrammarLSPPosition) { self.start = start; self.end = end } }
public struct GrammarTextDocumentChange: Codable, Equatable, Sendable { public let range: GrammarLSPRange?; public let text: String; public init(range: GrammarLSPRange? = nil, text: String) { self.range = range; self.text = text } }
public struct GrammarCompletionItem: Codable, Equatable, Sendable { public let label: String; public let kind: String }
