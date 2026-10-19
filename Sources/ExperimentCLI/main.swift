import Foundation
import GrammarReplLib

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func write(_ data: Data, to path: String, refusingReplacement: Bool = false) throws {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    if refusingReplacement, FileManager.default.fileExists(atPath: url.path) {
        fail("Refusing to replace existing project at \(url.path).")
    }
    try data.write(to: url, options: .atomic)
}

func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}

let usage = """
Usage: grammar-repl-experiment show|verify <artifact-or-project.json>
       grammar-repl-experiment project-create <project.json> <name>
       grammar-repl-experiment project-add <project.json> <id> <artifact.json>
"""
let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail(usage) }

do {
    switch command {
    case "show" where arguments.count == 2,
         "verify" where arguments.count == 2:
        let artifact = try REPLExperimentArtifact.decode(
            Data(contentsOf: URL(fileURLWithPath: arguments[1]))
        )
        switch (command, artifact) {
        case ("show", .document(let document)):
            print("\(document.fingerprint)  \(document.engines.count) engines  \(document.agreement.rawValue)")
        case ("show", .project(let project)):
            print("\(project.fingerprint)  \(project.experiments.count) experiments  \(project.name)")
            for entry in project.experiments {
                print("\(entry.id)  \(entry.experiment.fingerprint)  \(entry.experiment.agreement.rawValue)")
            }
        case ("verify", .document(let document)):
            let verification = try document.verify()
            try printJSON(verification)
            if !verification.matches { exit(1) }
        case ("verify", .project(let project)):
            let verification = try project.verify()
            try printJSON(verification)
            if !verification.matches { exit(1) }
        default:
            fatalError("Command validation must cover every artifact case.")
        }

    case "project-create" where arguments.count == 3:
        let project = try REPLExperimentProject.create(name: arguments[2])
        try write(project.json(), to: arguments[1], refusingReplacement: true)
        print(project.fingerprint)

    case "project-add" where arguments.count == 4:
        let project = try REPLExperimentProject.decode(
            Data(contentsOf: URL(fileURLWithPath: arguments[1]))
        )
        let experiment = try REPLExperimentDocument.decode(
            Data(contentsOf: URL(fileURLWithPath: arguments[3]))
        )
        let updated = try project.adding(id: arguments[2], experiment: experiment)
        try write(updated.json(), to: arguments[1])
        print(updated.fingerprint)

    default:
        fail(usage)
    }
} catch {
    fail("Experiment error: \(error)", code: 1)
}
