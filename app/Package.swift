// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TGHotkeyApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TGHotkeyApp",
            path: "Sources/TGHotkeyApp"
        )
    ]
)
