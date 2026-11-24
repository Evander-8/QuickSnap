// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "QuickSnap",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "QuickSnapCore",
            targets: ["QuickSnapCore"]
        ),
        .executable(
            name: "QuickSnap",
            targets: ["QuickSnap"]
        )
    ],
    targets: [
        .target(
            name: "QuickSnapCore",
            path: "Sources/QuickSnapCore",
            exclude: ["GEMINI.md"]
        ),
        .executableTarget(
            name: "QuickSnap",
            dependencies: ["QuickSnapCore"],
            path: "Sources/QuickSnap",
            exclude: [
                "App/GEMINI.md",
                "CaptureUI/GEMINI.md",
                "Panels/GEMINI.md"
            ]
        ),
        .testTarget(
            name: "QuickSnapTests",
            dependencies: ["QuickSnapCore"],
            path: "Tests/QuickSnapTests"
        )
    ]
)
