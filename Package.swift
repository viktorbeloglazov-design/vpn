// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KZTunnel",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "KZTunnelCore",
            path: "Sources/KZTunnelCore"
        ),
        .executableTarget(
            name: "kztunneld",
            dependencies: ["KZTunnelCore"],
            path: "Sources/KZTunnelHelper"
        ),
        .executableTarget(
            name: "KZTunnelApp",
            dependencies: ["KZTunnelCore"],
            path: "Sources/KZTunnelApp"
        ),
        .testTarget(
            name: "KZTunnelCoreTests",
            dependencies: ["KZTunnelCore"],
            path: "Tests/KZTunnelCoreTests"
        ),
    ]
)
