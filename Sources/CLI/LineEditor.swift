//
//  LineEditor.swift
//  Grammar-REPL
//
//  Created by Ulf Akerstedt-Inoue on 2026/07/66.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

#if os(macOS)
import Foundation
import Darwin
@preconcurrency import CReadline
import GrammarReplLib

final class LineEditor {
    private let historyPath: String
    nonisolated(unsafe) private static var activeSession = REPLSession()
    nonisolated(unsafe) private static var matches: [String] = []

    init() {
        historyPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grammar-repl-history").path
        _ = read_history(historyPath)
        grammar_repl_set_completion({ _, _, _ in
            let line = String(cString: grammar_repl_line_buffer())
            LineEditor.matches = CommandCompletion.candidates(for: line, session: LineEditor.activeSession)
            return rl_completion_matches("", { _, state in
                guard state >= 0, Int(state) < LineEditor.matches.count else { return nil }
                return strdup(LineEditor.matches[Int(state)])
            })
        })
    }

    deinit { _ = write_history(historyPath) }

    func read(prompt: String, session: REPLSession) -> String? {
        Self.activeSession = session
        guard let pointer = readline(prompt) else { return nil }
        defer { free(pointer) }
        let line = String(cString: pointer)
        if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { add_history(pointer) }
        return line
    }
}
#else
import GrammarREPLCore

final class LineEditor {
    func read(prompt: String, session: REPLSession) -> String? {
        print(prompt, terminator: "")
        return readLine()
    }
}
#endif
