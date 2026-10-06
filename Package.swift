// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiskCleaner",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DiskCleanerCore", targets: ["DiskCleanerCore"]),
    ],
    targets: [
        .target(name: "DiskCleanerCore"),
        .executableTarget(
            name: "DiskCleaner",
            dependencies: ["DiskCleanerCore"],
            resources: [.copy("Resources/app-icon.png")]
        ),
        .executableTarget(
            name: "DiskCleanerTests",
            dependencies: ["DiskCleanerCore"],
            path: "Tests/DiskCleanerCoreTests"
        ),
    ]
)
