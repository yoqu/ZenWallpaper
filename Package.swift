// swift-tools-version:5.9
import PackageDescription

// Why split into ZenWallpaperKit (library) + ZenWallpaper (executable)?
//
// On a CommandLineTools-only toolchain neither XCTest nor swift-testing link cleanly
// through SwiftPM, so the test runner is a plain `.executableTarget` (run via
// `swift run ZenWallpaperTests`). For that runner to reach internal symbols via
// `@testable import`, the code under test must live in a *library* target — two
// `.executableTarget`s can't share internal symbols at link time. So most of the
// source lives in the kit, and `ZenWallpaper` is just a thin `@main` shell over it.
let package = Package(
    name: "ZenWallpaper",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "ZenWallpaperKit",
            path: "Sources/ZenWallpaperKit",
            swiftSettings: [
                // `-enable-testing` makes internal symbols visible to `@testable import`
                // — used by both the app shell (`Sources/ZenWallpaper/ZenWallpaperApp.swift`)
                // and the test runner. We can't gate this to debug only because the
                // release build of the app target also does `@testable import` and would
                // otherwise hit "module was not compiled for testing".
                //
                // The flag is purely a compile-time visibility relaxation; it does not
                // change runtime behavior, binary size in any meaningful way, or expose
                // anything to third parties (this kit is only consumed by the executable
                // in this same package).
                .unsafeFlags(["-enable-testing"])
            ]
        ),
        .executableTarget(
            name: "ZenWallpaper",
            dependencies: ["ZenWallpaperKit"],
            path: "Sources/ZenWallpaper"
        ),
        .executableTarget(
            name: "ZenWallpaperTests",
            dependencies: ["ZenWallpaperKit"],
            path: "Tests/ZenWallpaperTests"
        )
    ]
)
