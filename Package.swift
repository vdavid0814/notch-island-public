// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "NotchIsland",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "NotchIsland", targets: ["NotchIsland"]),
    ],
    targets: [
        .target(
            name: "NotchIslandKit",
            swiftSettings: swiftSettings,
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("QuickLookThumbnailing"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .executableTarget(
            name: "NotchIsland",
            dependencies: ["NotchIslandKit"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "NotchIslandKitTests",
            dependencies: ["NotchIslandKit"],
            swiftSettings: swiftSettings
        ),
    ]
)
