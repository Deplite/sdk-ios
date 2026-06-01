// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Deplite",
    platforms: [
        .iOS(.v15), .macOS(.v12), .tvOS(.v15), .watchOS(.v8), .visionOS(.v1),
    ],
    products: [
        .library(name: "Deplite", targets: ["Deplite"]),
    ],
    targets: [
        .target(name: "Deplite", path: "Sources/Deplite"),
        .testTarget(name: "DepliteTests", dependencies: ["Deplite"], path: "Tests/DepliteTests"),
    ]
)
