// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "grammar-repl",
    platforms: [.macOS(.v13), .iOS(.v14)],
    products: [
        .executable(name: "grammar-repl", targets: ["grammar-repl"]),
        .executable(name: "grammar-repl-conformance", targets: ["grammar-repl-conformance"]),
        .library(name: "GrammarReplLib", targets: ["GrammarReplLib"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.2"),
        .package(url: "https://github.com/hakkabon/Grammar.git", .upToNextMinor(from: "0.2.0")),
        .package(url: "https://github.com/hakkabon/Parser.git", .upToNextMinor(from: "0.2.0")),
        .package(url: "https://github.com/hakkabon/Lexer.git", .upToNextMinor(from: "0.1.0")),
        .package(url: "https://github.com/hakkabon/Earley-Parser.git", .upToNextMinor(from: "0.1.0")),
        .package(url: "https://github.com/hakkabon/CYK-Parser.git", .upToNextMinor(from: "0.1.0")),
        .package(url: "https://github.com/hakkabon/RNGLR-Parser.git", .upToNextMinor(from: "0.1.0")),
        .package(url: "https://github.com/hakkabon/LR-Parsing.git", .upToNextMinor(from: "0.1.2")),
        .package(url: "https://github.com/hakkabon/GrammarDiagram.git", .upToNextMinor(from: "0.1.0")),
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
                .product(name: "GrammarDiagram", package: "GrammarDiagram"),
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
                .product(name: "LR-Parsing", package: "LR-Parsing"),
            ]
        ),
    ]
)
