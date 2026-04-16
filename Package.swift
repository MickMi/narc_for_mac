// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NARC",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "NARC",
            dependencies: [],
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
