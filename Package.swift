// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "LightTTS", platforms: [.macOS("14.2")], products: [.library(name: "LightTTSRuntime", targets: ["LightTTSRuntime"]), .executable(name: "LightTTS", targets: ["LightTTS"]), .executable(name: "lighttts-cli", targets: ["LightTTSCLI"]), .executable(name: "LightTTSEngine", targets: ["LightTTSEngine"])], dependencies: [.package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "6b516c3dbf6275cff692ea38bed2bd5764ea74cd"), .package(url: "https://github.com/k2-fsa/sherpa-onnx.git", exact: "2.0.1")], targets: [
    .binaryTarget(name: "whisper", url: "https://github.com/ggml-org/whisper.cpp/releases/download/v1.7.5/whisper-v1.7.5-xcframework.zip", checksum: "c7faeb328620d6012e130f3d705c51a6ea6c995605f2df50f6e1ad68c59c6c4a"),
    .target(name: "LightTTSCore", resources: [.process("Resources")]),
    .target(name: "LightTTSRuntime", dependencies: ["LightTTSCore"]),
    .target(name: "LightTTSInference", dependencies: ["LightTTSCore", .product(name: "FluidAudio", package: "FluidAudio"), .product(name: "sherpa-onnx", package: "sherpa-onnx"), "whisper"]),
    .executableTarget(name: "LightTTSEngine", dependencies: ["LightTTSInference", .product(name: "FluidAudio", package: "FluidAudio")]),
    .executableTarget(name: "LightTTS", dependencies: ["LightTTSCore", "LightTTSRuntime"], resources: [.process("Resources")]),
    .executableTarget(name: "LightTTSCLI", dependencies: ["LightTTSCore", "LightTTSInference", .product(name: "FluidAudio", package: "FluidAudio")]),
    .executableTarget(name: "model-validation", dependencies: ["LightTTSCore", "LightTTSInference"]),
    .executableTarget(name: "cloud-validation", dependencies: ["LightTTSCore", "LightTTSInference"]),
    .testTarget(name: "AppTests", dependencies: ["LightTTS"]),
    .testTarget(name: "CoreTests", dependencies: ["LightTTSCore"]),
    .testTarget(name: "RuntimeTests", dependencies: ["LightTTSRuntime"])
])
