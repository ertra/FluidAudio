// swift-tools-version: 6.0
import PackageDescription
import Foundation

let package = Package(
    name: "FluidAudio",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "FluidAudio",
            targets: ["FluidAudio"]
        ),
        .executable(
            name: "fluidaudiocli",
            targets: ["FluidAudioCLI"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FluidAudio",
            dependencies: [
                "FastClusterWrapper",
                "MachTaskSelfWrapper",
                "NemoTextProcessing",
            ],
            path: "Sources/FluidAudio",
            // Echo99 does not use LuxTTS. Exclude its implementation and resources
            // at package planning time, before compilation or resource copying.
            exclude: ["ASR/Parakeet/Unified/benchmark.md", "TTS/LuxTts"]
        ),
        // Byte-exact NeMo text normalization (FST engine, all 7 languages).
        // Prebuilt xcframework from FluidInference/text-processing-rs v0.3.0.
        // Always linked on tools < 6.2; Package@swift-6.2.swift exposes it as
        // the opt-out `NemoTextProcessing` trait (#880, #888).
        .binaryTarget(
            name: "NemoTextProcessing",
            url:
                "https://github.com/FluidInference/text-processing-rs/releases/download/v0.3.0/NemoTextProcessing.xcframework.zip",
            checksum: "76d0ee9a32b1ee2193231299180ca9bc4fc7e98794e771b3d55d66498352d85f"
        ),
        .target(
            name: "FastClusterWrapper",
            path: "Sources/FastClusterWrapper",
            publicHeadersPath: "include"
        ),
        .target(
            name: "MachTaskSelfWrapper",
            path: "Sources/MachTaskSelfWrapper",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "FluidAudioCLI",
            dependencies: ["FluidAudio"],
            path: "Sources/FluidAudioCLI",
            exclude: ["README.md", "Commands/TTS/LuxTtsG2pDumpCommand.swift"],
            resources: [
                .process("Utils/english.json")
            ]
        ),
        .testTarget(
            name: "FluidAudioTests",
            dependencies: [
                "FluidAudio",
                "FluidAudioCLI",
            ],
            exclude: ["TTS/LuxTts"],
            resources: [
                // Real recordings (cleared for public release by the speaker) for the
                // streaming final-window regression, issue #855.
                .copy("ASR/Parakeet/SlidingWindow/Fixtures")
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
