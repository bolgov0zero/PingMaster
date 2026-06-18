// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PingMaster",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PingMaster",
            path: "Sources/PingMaster",
            resources: [
                .process("../../Resources/Info.plist")
            ]
        )
    ]
)
