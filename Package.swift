// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotificationCharacter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "NotificationCharacter", targets: ["NotificationCharacter"]),
        .executable(name: "BundleApp", targets: ["BundleApp"]),
    ],
    targets: [
        .target(name: "NotificationCore"),
        .executableTarget(name: "NotificationCharacter", dependencies: ["NotificationCore"]),
        .executableTarget(name: "BundleApp"),
        .testTarget(name: "NotificationCoreTests", dependencies: ["NotificationCore"]),
    ],
    swiftLanguageModes: [.v5]
)
