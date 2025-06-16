// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AuralKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(
            name: "AuralKit",
            targets: ["AuralKit"]
        )
    ],
    targets: [
        .target(
            name: "AuralKit",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "AuralKitTests",
            dependencies: ["AuralKit"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)