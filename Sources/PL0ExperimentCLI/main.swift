import Foundation
import PL0FrontendConformance

@main
struct GrammarREPLPL0ExperimentCLI {
    static func main() async throws {
        let report = try await PL0FrontendExperimentSuite.run(frontendID: "grammar-repl")
        let data = try report.json()
        if let output = CommandLine.arguments.dropFirst().first {
            try data.write(to: URL(fileURLWithPath: output), options: .atomic)
        } else {
            print(String(decoding: data, as: UTF8.self))
        }
    }
}
