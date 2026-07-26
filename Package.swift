// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "grammar-repl",
    platforms: [.macOS(.v13), .iOS(.v14)],
    products: [
        .executable(name: "grammar-repl", targets: ["grammar-repl"]),
        .library(name: "GrammarReplLib", targets: ["GrammarReplLib"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.2"),
        .package(url: "https://github.com/hakkabon/Grammar.git", branch: "main"),
        .package(url: "https://github.com/hakkabon/Parser.git", branch: "main"),
        .package(url: "https://github.com/hakkabon/Lexer-FSA.git", branch: "main"),
        .package(url: "https://github.com/hakkabon/Earley-Parser.git", branch: "main"),
        .package(url: "https://github.com/hakkabon/CYK-Parser.git", branch: "main"),
        .package(url: "https://github.com/hakkabon/RNGLR-Parser.git", branch: "main"),
        .package(url: "https://github.com/hakkabon/LR-Parsing.git", branch: "main"),
        .package(url: "https://github.com/hakkabon/GrammarDiagram.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "GrammarReplLib",
            dependencies: [
                .product(name: "Grammar", package: "Grammar"),
                .product(name: "Parser", package: "Parser"),
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
