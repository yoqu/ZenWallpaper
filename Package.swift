// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ZenWallpaper",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ZenWallpaper",
            path: "Sources/ZenWallpaper"
        )
    ]
)
