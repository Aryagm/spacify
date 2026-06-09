// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SpotifyNativeSpatial",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "SpotifyNativeSpatialCore",
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AudioUnit")
            ]
        ),
        .executableTarget(
            name: "SpotifyNativeSpatial",
            dependencies: ["SpotifyNativeSpatialCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AudioUnit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMotion"),
                .linkedFramework("SwiftUI"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "SpotifyNativeSpatialCoreTests",
            dependencies: ["SpotifyNativeSpatialCore"]
        )
    ]
)
