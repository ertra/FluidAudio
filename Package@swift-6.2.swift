// swift-tools-version: 6.2
import PackageDescription
import Foundation

let package = Package(
    name: "FluidAudio",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .visionOS(.v2),
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
            ],
            path: "Sources/FluidAudio",
            // Echo99 uses PocketTTS. Keep shared helpers; exclude other synthesis engines.
            exclude: [
                "ASR/Parakeet/Unified/benchmark.md", "TTS/LuxTts",
                "TTS/KokoroAne", "TTS/StyleTTS2", "TTS/Supertonic3", "TTS/NeuTts", "TTS/Inflect",
                "TTS/Chatterbox", "TTS/Paradee",
            ]
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
            exclude: ["README.md", "Commands/TTS/LuxTtsG2pDumpCommand.swift", "Commands/TTSAsrVerifyCommand.swift"],
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
            exclude: [
                "TTS/LuxTts", "TTS/KokoroAne", "TTS/StyleTTS2", "TTS/Supertonic3",
                "TTS/Inflect", "TTS/NeuTtsTokenizerTests.swift", "TTS/Chatterbox", "TTS/Paradee",
            ],
            resources: [
                .process("TTS/PocketTTS/Fixtures"),
                // Real recordings (cleared for public release by the speaker) for the
                // streaming final-window regression, issue #855.
                .copy("ASR/Parakeet/SlidingWindow/Fixtures"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
