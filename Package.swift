// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "codeagent-meter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodeAgentMeterApp", targets: ["CodeAgentMeterApp"])
    ],
    targets: [
        .target(
            name: "CodeAgentMeterCore"
        ),
        .executableTarget(
            name: "CodeAgentMeterApp",
            dependencies: ["CodeAgentMeterCore"]
        ),
        .testTarget(
            name: "CodeAgentMeterCoreTests",
            dependencies: ["CodeAgentMeterCore"]
        ),
    ]
)
