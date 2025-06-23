// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "AuralKit",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
    .visionOS(.v1),
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
    ),
  ]
)
