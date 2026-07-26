import ArgumentParser
import GrammarREPLCore

@main
struct GrammarRepl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "grammar-repl",
        abstract: "Inspect grammars, generated LR automata, and parser outcomes.",
        version: "0.1.0"
    )

    static func main() { GrammarREPL().run() }
}
