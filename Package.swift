// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "grammar-repl",
    platforms: [.macOS(.v13), .iOS(.v14)],
    products: [
        .executable(name: "grammar-repl", targets: ["grammar-repl"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.2"),
        .package(url: "https://github.com/hakkabon/Grammar.git", branch: "main"),
        .package(url: "https://github.com/hakkabon/Parser.git", branch: "main"),
        .package(url: "https://github.com/hakkabon/Lexer-FSA.git", branch: "main"),
        .package(url: "https://github.com/hakkabon/Earley-Parser.git", branch: "main"),
        .package(url: "https://github.com/hakkabon/CYK-Parser.git", branch: "main"),
        .package(url: "https://github.com/hakkabon/RNGLR-Parser.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "grammar-repl",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Grammar", package: "Grammar"),
                .product(name: "Parser", package: "Parser"),
                .product(name: "Earley-Parser", package: "Earley-Parser"),
                .product(name: "CYK-Parser", package: "CYK-Parser"),
                .product(name: "RNGLR-Parser", package: "RNGLR-Parser"),
            ]
        ),
    ]
)
