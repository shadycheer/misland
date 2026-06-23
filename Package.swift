// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "misland",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "misland",
            path: "Sources/misland"
        ),
        .testTarget(
            name: "mislandTests",
            dependencies: ["misland"],
            path: "Tests/mislandTests"
        )
    ]
)
