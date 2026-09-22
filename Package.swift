// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KupibasVPN",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "KupibasCore",
            path: "Sources/KupibasCore"
        ),
        .executableTarget(
            name: "kupibasvpnd",
            dependencies: ["KupibasCore"],
            path: "Sources/KupibasHelper"
        ),
        .executableTarget(
            name: "KupibasVPNApp",
            dependencies: ["KupibasCore"],
            path: "Sources/KupibasApp"
        ),
        .executableTarget(
            name: "KupibasUninstaller",
            dependencies: ["KupibasCore"],
            path: "Sources/KupibasUninstaller"
        ),
        .testTarget(
            name: "KupibasCoreTests",
            dependencies: ["KupibasCore"],
            path: "Tests/KupibasCoreTests"
        ),
    ]
)
