import Foundation
import GrammarReplLib

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

guard CommandLine.arguments.count == 3,
      ["show", "verify"].contains(CommandLine.arguments[1]) else {
    fail("Usage: grammar-repl-experiment show|verify <artifact.json>")
}

do {
    let document = try REPLExperimentDocument.decode(
        Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    )
    if CommandLine.arguments[1] == "show" {
        print("\(document.fingerprint)  \(document.engines.count) engines  \(document.agreement.rawValue)")
    } else {
        let verification = try document.verify()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(verification), as: UTF8.self))
        if !verification.matches { exit(1) }
    }
} catch {
    fail("Experiment error: \(error)", code: 1)
}
