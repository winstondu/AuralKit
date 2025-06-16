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
        ),
        .executable(
            name: "AuralKitSample",
            targets: ["AuralKitSample"]
        )
    ],
    targets: [
        .target(
            name: "AuralKit",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("AccessLevelOnImport")
            ]
        ),
        .executableTarget(
            name: "AuralKitSample",
            dependencies: ["AuralKit"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("AccessLevelOnImport")
            ]
        ),
        .testTarget(
            name: "AuralKitTests",
            dependencies: ["AuralKit"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("AccessLevelOnImport")
            ]
        )
    ]
)