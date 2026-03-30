// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceClaude",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CSherpaOnnx",
            path: "Sources/CSherpaOnnx",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "VoiceClaude",
            dependencies: ["CSherpaOnnx"],
            path: "Sources/VoiceClaude",
            linkerSettings: [
                .unsafeFlags([
                    "-L", "Dependencies/sherpa-onnx/lib",
                    "-lsherpa-onnx-c-api",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]
        )
    ]
)
