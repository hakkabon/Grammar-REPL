//
//  repl.swift
//  Grammar-REPL
//
//  Created by Ulf Akerstedt-Inoue on 2026/07/25.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation
import ArgumentParser

@main
struct GrammarRepl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "grammar-repl",
        abstract: "Parse, compile, and execute source with the Grammar/Lexer/Parser toolchain.",
        version: "0.0.1"
    )

    static func main() {
        GrammarREPL().run()
    }

}
