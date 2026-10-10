// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PacerCore",
    products: [.library(name: "PacerCore", targets: ["PacerCore"])],
    targets: [
        .target(name: "PacerCore"),
        .testTarget(name: "PacerCoreTests", dependencies: ["PacerCore"])
    ]
)
