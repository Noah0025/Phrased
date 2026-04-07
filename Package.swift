// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Phrased",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Phrased",
            path: "Sources/Phrased",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PhrasedTests",
            dependencies: ["Phrased"],
            path: "Tests/PhrasedTests"
        )
    ]
)
