// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GhostMouse",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GhostMouse", targets: ["GhostMouse"])
    ],
    targets: [
        .executableTarget(
            name: "GhostMouse",
            path: "Sources/GhostMouse",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
