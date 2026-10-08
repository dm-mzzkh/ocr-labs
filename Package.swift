// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VisionLab",
    platforms: [.macOS(.v15), .iOS(.v18)],
    targets: [
        .target(name: "VisionLab"),
        .executableTarget(
            name: "SelfCheck",
            dependencies: ["VisionLab"]
        ),
        .executableTarget(
            name: "CheckerCLI",
            dependencies: ["VisionLab"]
        )
    ]
)
