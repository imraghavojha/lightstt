// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "LightTTS", platforms: [.macOS("14.2")], products: [.executable(name: "LightTTS", targets: ["LightTTS"]), .executable(name: "lighttts-cli", targets: ["LightTTSCLI"])], dependencies: [.package(url: "https://github.com/CJStanfield/CoreAudioTapKit.git", revision: "aab395f1e8e5dd1bd369c3bbfcf5c6bdca85e099"), .package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "6b516c3dbf6275cff692ea38bed2bd5764ea74cd")], targets: [
    .binaryTarget(name: "whisper", url: "https://github.com/ggml-org/whisper.cpp/releases/download/v1.7.5/whisper-v1.7.5-xcframework.zip", checksum: "c7faeb328620d6012e130f3d705c51a6ea6c995605f2df50f6e1ad68c59c6c4a"),
    .target(name: "LightTTSCore", dependencies: [.product(name: "FluidAudio", package: "FluidAudio"), "whisper"], resources: [.process("Resources")]),
    .executableTarget(name: "LightTTS", dependencies: ["LightTTSCore", .product(name: "CoreAudioTapKit", package: "CoreAudioTapKit")]),
    .executableTarget(name: "LightTTSCLI", dependencies: ["LightTTSCore"]),
    .executableTarget(name: "model-validation", dependencies: ["LightTTSCore"])
])
