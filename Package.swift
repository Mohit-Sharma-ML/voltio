// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Voltio",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "PowerCore", targets: ["PowerCore"]),
        .executable(name: "Voltio", targets: ["Voltio"]),
        .executable(name: "VoltioWidgets", targets: ["VoltioWidgets"]),
    ],
    targets: [
        .target(name: "PowerCore"),
        .executableTarget(
            name: "Voltio",
            dependencies: ["PowerCore"]
        ),
        // Widget extension. Built as a plain executable by SPM, then packaged
        // into an .appex by scripts/build_app.sh (no .xcodeproj in this repo).
        // The -e _NSExtensionMain entry point is REQUIRED on macOS 26: the
        // extension runtime resolves _NSExtensionMain (as Xcode-built appex
        // binaries do); with Swift's default _main entry the bundle boots,
        // cannot serve its descriptor to chronod, and exits within ~3s —
        // so the widgets never appear in the Edit Widgets gallery.
        .executableTarget(
            name: "VoltioWidgets",
            dependencies: ["PowerCore"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])
            ]
        ),
        .testTarget(
            name: "PowerCoreTests",
            dependencies: ["PowerCore"]
        ),
        .testTarget(
            name: "VoltioTests",
            dependencies: ["Voltio"]
        ),
    ]
)
