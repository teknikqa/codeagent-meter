// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ai-usage-meter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AIUsageMeterApp", targets: ["AIUsageMeterApp"])
    ],
    targets: [
        .target(
            name: "AIUsageMeterCore"
        ),
        .executableTarget(
            name: "AIUsageMeterApp",
            dependencies: ["AIUsageMeterCore"]
        ),
        .testTarget(
            name: "AIUsageMeterCoreTests",
            dependencies: ["AIUsageMeterCore"]
        ),
    ]
)
