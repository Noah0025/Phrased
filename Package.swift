// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Murmur",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Murmur",
            path: "Sources/InterviewCopilot",
            resources: [
                .copy("Resources/interview_context.txt")
            ]
        )
    ]
)
