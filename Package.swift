// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AuralKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2)
    ],
    products: [
        .library(
            name: "AuralKit",
            targets: ["AuralKit"]
        )
    ],
    targets: [
        .target(
            name: "AuralKit"
        ),
        .testTarget(
            name: "AuralKitTests",
            dependencies: ["AuralKit"]
        )
    ]
)