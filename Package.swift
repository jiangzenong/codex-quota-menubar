// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexQuotaMenuBar",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "QuotaCore", targets: ["QuotaCore"]),
        .executable(name: "CodexQuotaMenuBar", targets: ["QuotaMenuBar"]),
    ],
    targets: [
        .target(name: "QuotaCore"),
        .executableTarget(name: "QuotaMenuBar", dependencies: ["QuotaCore"]),
        .testTarget(name: "QuotaCoreTests", dependencies: ["QuotaCore"]),
        .testTarget(name: "QuotaMenuBarTests", dependencies: ["QuotaMenuBar", "QuotaCore"]),
    ]
)
