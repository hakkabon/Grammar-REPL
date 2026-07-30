//
//  GrammarDirectives.swift
//  Grammar-REPL
//
//  Created by Ulf Akerstedt-Inoue on 2026/07/66.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import LR_Parsing

/// Workbench directives are deliberately removed before the underlying
/// notation parser sees the grammar, keeping Grammar's formats unchanged.
/// Levels increase in declaration order, as in yacc-compatible grammars.
public struct GrammarDirectiveSet {
    public let precedence: LRPrecedenceSpecification

    public init(precedence: LRPrecedenceSpecification = .init(levels: [])) {
        self.precedence = precedence
    }
}

public struct PreprocessedGrammarSource {
    public let grammarSource: String
    public let directives: GrammarDirectiveSet
}

public enum GrammarDirectiveError: Error, CustomStringConvertible {
    case malformed(line: Int, text: String)

    public var description: String {
        switch self { case .malformed(let line, let text): "Malformed grammar directive at line \(line): \(text)" }
    }
}

public enum GrammarDirectiveParser {
    public static func parse(_ source: String) throws -> PreprocessedGrammarSource {
        var grammarLines: [String] = []
        var levels: [LRPrecedenceLevel] = []
        for (offset, line) in source.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("%") else { grammarLines.append(line); continue }
            let words = tokenize(String(trimmed.dropFirst()))
            guard let directive = words.first?.lowercased(), words.count > 1 else {
                throw GrammarDirectiveError.malformed(line: offset + 1, text: line)
            }
            let associativity: LRAssociativity
            switch directive {
            case "left": associativity = .left
            case "right": associativity = .right
            case "nonassoc", "none": associativity = .nonAssociative
            default: throw GrammarDirectiveError.malformed(line: offset + 1, text: line)
            }
            let terminals = Set(words.dropFirst().map(Terminal.init(string:)))
            levels.append(LRPrecedenceLevel(levels.count + 1, associativity: associativity, terminals: terminals))
            // Preserve line numbers for diagnostics produced by the notation parser.
            grammarLines.append("")
        }
        return PreprocessedGrammarSource(
            grammarSource: grammarLines.joined(separator: "\n"),
            directives: GrammarDirectiveSet(precedence: .init(levels: levels))
        )
    }

    private static func tokenize(_ text: String) -> [String] {
        var words: [String] = [], word = "", quote: Character?
        for character in text {
            if let active = quote {
                if character == active { quote = nil } else { word.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !word.isEmpty { words.append(word); word = "" }
            } else { word.append(character) }
        }
        if !word.isEmpty { words.append(word) }
        return words
    }
}
