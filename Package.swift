// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NARC",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Embedded terminal emulator — fork a child process with a PTY and render
        // xterm-compatible output as an NSView. Used by Dashboard to host real
        // claude/zsh sessions inside NARC instead of orchestrating external iTerm.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "NARC",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "NARC/Sources",
            resources: [
                .process("../Resources")
            ]
        ),
        .testTarget(
            name: "NARCTests",
            dependencies: ["NARC"],
            path: "NARC/Tests"
        )
    ]
)
