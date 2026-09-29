// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pipelines",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Pipelines", targets: ["Pipelines"])],
    targets: [
        .executableTarget(name: "Pipelines"),
        .testTarget(name: "PipelinesTests", dependencies: ["Pipelines"])
    ]
)
