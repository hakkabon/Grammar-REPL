import IncrementalParsing
import LanguageTooling

/// Host-facing adoption boundary for external language kits. Grammar-REPL can
/// inspect a provider without importing its parser, semantic, or compiler
/// implementation details.
public struct GrammarREPLToolingConsumer: Sendable {
    public let document: LanguageToolingDocument

    public init(provider: any LanguageToolingProvider) {
        document = LanguageToolingDocument(provider: provider)
    }

    public var descriptor: LanguageProviderDescriptor { document.descriptor }

    @discardableResult
    public func open(_ snapshot: SourceSnapshot) async throws
        -> LanguageProviderAnalysis {
        try await document.open(snapshot)
    }

    @discardableResult
    public func apply(_ edit: SourceEdit) async throws
        -> LanguageProviderAnalysis {
        try await document.apply(edit)
    }

    public func completions(at position: ToolingPosition) async throws
        -> [ToolingCompletionItem] {
        try await document.completions(at: position)
    }

    public func semanticTokens() async throws -> ToolingSemanticTokensResult {
        try await document.semanticTokens()
    }
}
