// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AgentGlance",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "AgentGlanceCore"),
        .executableTarget(name: "AgentGlance", dependencies: ["AgentGlanceCore"]),
        .executableTarget(name: "agent-glance-hook"),
        .testTarget(name: "AgentGlanceCoreTests", dependencies: ["AgentGlanceCore"]),
    ],
    swiftLanguageModes: [.v6]
)
