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
        .package(url: "https://github.com/hakkabon/Grammar.git", revision: "69f85d7a493e1862412c34493e3656e94331df06"),
        .package(url: "https://github.com/hakkabon/Parser.git", revision: "3663097550f3ed1b8dcad8a26f4c2c55cc61b4e1"),
        .package(url: "https://github.com/hakkabon/Lexer-FSA.git", revision: "5289a38e507bbf63863699a1eb9ac7a4d19aafba"),
        .package(url: "https://github.com/hakkabon/Earley-Parser.git", revision: "7e1845c9531274ecab8201db5613eb10e149a5e2"),
        .package(url: "https://github.com/hakkabon/CYK-Parser.git", revision: "5c375aea8c68edd5b344f89c38cc33668a49d1cd"),
        .package(url: "https://github.com/hakkabon/RNGLR-Parser.git", revision: "d16e7910f6e807d66b54acf5848f894bebf9bc5b"),
        .package(url: "https://github.com/hakkabon/LR-Parsing.git", revision: "054c0b7b5acdac31814034d2271660fcdc86a092"),
        .package(url: "https://github.com/hakkabon/GrammarDiagram.git", revision: "dc17ab061a1614ba0692be06aa69043b45bbbcd4"),
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
