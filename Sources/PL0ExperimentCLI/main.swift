import Foundation
import PL0FrontendConformance

@main
struct GrammarREPLPL0ExperimentCLI {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "product-campaign" {
            let report = try await PL0ProductCampaign.run()
            let data = try report.json()
            if arguments.count > 1 {
                try data.write(
                    to: URL(fileURLWithPath: arguments[1]), options: .atomic)
            } else {
                print(String(decoding: data, as: UTF8.self))
            }
            return
        }
        if arguments.first == "grammar-campaign" {
            let data = try await PL0ProductCampaign.runGrammarHotReload().json()
            if arguments.count > 1 {
                try data.write(
                    to: URL(fileURLWithPath: arguments[1]), options: .atomic)
            } else {
                print(String(decoding: data, as: UTF8.self))
            }
            return
        }
        if arguments.first == "product-budgets" {
            let data = try PL0ProductCampaign.releaseBudgetJSON()
            if arguments.count > 1 {
                try data.write(
                    to: URL(fileURLWithPath: arguments[1]), options: .atomic)
            } else {
                print(String(decoding: data, as: UTF8.self))
            }
            return
        }
        let report = try await PL0FrontendExperimentSuite.run(frontendID: "grammar-repl")
        let data = try report.json()
        if let output = arguments.first {
            try data.write(to: URL(fileURLWithPath: output), options: .atomic)
        } else {
            print(String(decoding: data, as: UTF8.self))
        }
    }
}
