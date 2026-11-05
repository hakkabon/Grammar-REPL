// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "grammar-repl",
    platforms: [.macOS(.v13), .iOS(.v14)],
    products: [
        .executable(name: "grammar-repl", targets: ["grammar-repl"]),
        .executable(name: "grammar-repl-conformance", targets: ["grammar-repl-conformance"]),
        .executable(name: "grammar-repl-experiment", targets: ["grammar-repl-experiment"]),
        .executable(name: "grammar-repl-pl0-experiment", targets: ["grammar-repl-pl0-experiment"]),
        .library(name: "GrammarReplLib", targets: ["GrammarReplLib"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.2"),
        .package(path: "../Grammar"),
        .package(path: "../Parser"),
        .package(path: "../Lexer"),
        .package(path: "../Earley-Parser"),
        .package(path: "../CYK-Parser"),
        .package(path: "../RNGLR-Parser"),
        .package(path: "../LR-Parsing"),
        .package(path: "../LL-Parsing"),
        .package(path: "../Earley-TableParser"),
        .package(url: "https://github.com/hakkabon/GrammarDiagram.git", .upToNextMinor(from: "0.1.0")),
        .package(path: "../Compiler"),
        .package(path: "../PL0-LanguageKit"),
        .package(path: "../Incremental-Parsing"),
    ],
    targets: [
        .target(
            name: "GrammarReplLib",
            dependencies: [
                .product(name: "Grammar", package: "Grammar"),
                .product(name: "Parser", package: "Parser"),
                .product(name: "Lexer", package: "Lexer"),
                .product(name: "Earley-Parser", package: "Earley-Parser"),
                .product(name: "CYK-Parser", package: "CYK-Parser"),
                .product(name: "RNGLR-Parser", package: "RNGLR-Parser"),
                .product(name: "LR-Parsing", package: "LR-Parsing"),
                .product(name: "LL-Parsing", package: "LL-Parsing"),
                .product(name: "Earley-TableParser", package: "Earley-TableParser"),
                .product(name: "GrammarDiagram", package: "GrammarDiagram"),
                .product(name: "Compiler", package: "Compiler"),
                .product(name: "IncrementalParsing", package: "Incremental-Parsing"),
            ],
            path: "Sources/GrammarReplLib"
        ),
        .executableTarget(
            name: "grammar-repl",
            dependencies: [
                "GrammarReplLib",
                "CReadline",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/CLI"
        ),
        .executableTarget(
            name: "grammar-repl-conformance",
            dependencies: ["GrammarReplLib"],
            path: "Sources/Conformance"
        ),
        .executableTarget(
            name: "grammar-repl-experiment",
            dependencies: ["GrammarReplLib"],
            path: "Sources/ExperimentCLI"
        ),
        .executableTarget(
            name: "grammar-repl-pl0-experiment",
            dependencies: [
                .product(name: "PL0FrontendConformance", package: "PL0-LanguageKit"),
                .product(name: "IncrementalParsing", package: "Incremental-Parsing"),
            ],
            path: "Sources/PL0ExperimentCLI"
        ),
        .systemLibrary(
            name: "CReadline",
            path: "Sources/CReadline",
            pkgConfig: "libedit"
        ),
        .testTarget(
            name: "GrammarReplLibTests",
            dependencies: [
                "GrammarReplLib",
                .product(name: "Grammar", package: "Grammar"),
                .product(name: "Parser", package: "Parser"),
                .product(name: "LR-Parsing", package: "LR-Parsing"),
                .product(name: "IncrementalParsing", package: "Incremental-Parsing"),
            ]
        ),
    ]
)
