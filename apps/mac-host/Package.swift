// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ClawdexHost",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ClawdexHost", targets: ["ClawdexHost"])
    ],
    targets: [
        .executableTarget(
            name: "ClawdexHost",
            resources: [
                .copy("Resources/Bundled")
            ]
        ),
        .testTarget(
            name: "ClawdexHostTests",
            dependencies: ["ClawdexHost"]
        )
    ]
)
