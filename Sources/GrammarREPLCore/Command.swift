import Foundation
import LR_Parsing

public enum REPLParser: String, CaseIterable, Equatable {
    case earley, cyk, rnglr, lr0, slr, lalr, lr1

    public var lrAlgorithm: LRParser.Algorithm? {
        switch self {
        case .lr0: .lr0
        case .slr: .slr
        case .lalr: .lalr
        case .lr1: .lr1
        default: nil
        }
    }
}

public enum REPLNotation: String, CaseIterable { case bnf, ebnf, wsn, gen }

public enum REPLCommand: Equatable {
    case help, quit, reload, grammar, check, conflicts, settings, history
    case load(path: String, start: String?)
    case parser(REPLParser?)
    case first(String), follow(String), predict(String), parse(String)
    case tree(Int?), state(Int?), explain(Int?), replay(Int?)
    case diagram(String), export(artifact: String, path: String)
    case trace(String?), identity(String), precedence(String)
    case unknown(String)

    public static func decode(_ line: String) -> REPLCommand {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .unknown("") }
        guard text.first == ":" else { return .parse(text) }
        let body = text.dropFirst()
        let split = body.firstIndex(where: \.isWhitespace)
        let name = String(split.map { body[..<$0] } ?? body[...]).lowercased()
        let argument = split.map { String(body[$0...]).trimmingCharacters(in: .whitespaces) } ?? ""
        switch name {
        case "help", "?": return .help
        case "quit", "exit", "q": return .quit
        case "load":
            let words = shellWords(argument)
            return words.isEmpty ? .unknown(text) : .load(path: words[0], start: words.count > 1 ? words[1] : nil)
        case "reload": return .reload
        case "grammar": return .grammar
        case "parser": return .parser(REPLParser(rawValue: argument.lowercased()))
        case "check": return .check
        case "conflicts": return .conflicts
        case "first": return .first(argument)
        case "follow": return .follow(argument)
        case "predict": return .predict(argument)
        case "parse": return .parse(unquote(argument))
        case "tree": return .tree(argument.isEmpty ? nil : Int(argument))
        case "state": return .state(argument.isEmpty ? nil : Int(argument))
        case "explain": return .explain(argument.isEmpty ? nil : Int(argument))
        case "replay": return .replay(argument.isEmpty ? nil : Int(argument))
        case "settings": return .settings
        case "history": return .history
        case "diagram": return .diagram(argument)
        case "export":
            let words = shellWords(argument)
            return words.count == 2 ? .export(artifact: words[0], path: words[1]) : .unknown(text)
        case "trace": return .trace(argument.isEmpty ? nil : argument)
        case "identity": return .identity(argument)
        case "precedence": return .precedence(argument)
        default: return .unknown(text)
        }
    }

    private static func unquote(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, first == text.last, first == "\"" || first == "'" else { return text }
        return String(text.dropFirst().dropLast())
    }

    private static func shellWords(_ text: String) -> [String] {
        var result: [String] = [], word = ""
        var quote: Character?
        for character in text {
            if let active = quote {
                if character == active { quote = nil } else { word.append(character) }
            } else if character == "\"" || character == "'" { quote = character
            } else if character.isWhitespace {
                if !word.isEmpty { result.append(word); word = "" }
            } else { word.append(character) }
        }
        if !word.isEmpty { result.append(word) }
        return result
    }
}
