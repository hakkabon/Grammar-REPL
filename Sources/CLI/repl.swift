//
//  repl.swift
//  Grammar-REPL
//
//  Created by Ulf Akerstedt-Inoue on 2026/07/66.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import ArgumentParser
import GrammarReplLib

@main
struct GrammarRepl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "grammar-repl",
        abstract: "Inspect grammars, generated LR automata, and parser outcomes.",
        version: "0.1.0"
    )

    static func main() {
        let editor = LineEditor()
        GrammarREPL(readCommand: editor.read).run()
    }
}
