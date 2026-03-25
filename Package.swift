// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "YTDLPGUI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "YTDLPGUI", targets: ["YTDLPGUI"])
    ],
    targets: [
        .executableTarget(
            name: "YTDLPGUI",
            path: "Sources/YTDLPGUI"
        ),
        .testTarget(
            name: "YTDLPGUITests",
            dependencies: ["YTDLPGUI"],
            path: "Tests/YTDLPGUITests"
        )
    ]
)
