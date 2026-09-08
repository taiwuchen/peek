// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PeekKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PeekCore", targets: ["PeekCore"]),
        .library(name: "PeekCapture", targets: ["PeekCapture"]),
        .library(name: "PeekProviders", targets: ["PeekProviders"]),
        .library(name: "PeekUI", targets: ["PeekUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.4.1"),
    ],
    targets: [
        .target(name: "PeekCore"),
        .target(name: "PeekCapture", dependencies: ["PeekCore"]),
        .target(name: "PeekProviders", dependencies: ["PeekCore"]),
        .target(
            name: "PeekUI",
            dependencies: ["PeekCore", "KeyboardShortcuts", .product(name: "MarkdownUI", package: "swift-markdown-ui")],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "PeekCoreTests", dependencies: ["PeekCore"]),
        .testTarget(name: "PeekCaptureTests", dependencies: ["PeekCapture"]),
        .testTarget(name: "PeekProvidersTests", dependencies: ["PeekProviders"]),
        .testTarget(name: "PeekUITests", dependencies: ["PeekUI"]),
    ],
    swiftLanguageModes: [.v6]
)
