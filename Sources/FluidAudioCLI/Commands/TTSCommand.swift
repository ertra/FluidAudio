import CoreML
import FluidAudio
import Foundation

public struct TTS {

    private static let logger = AppLogger(category: "TTSCommand")
    private static let artifactsDirectoryName = "fluidaudio_cli"

    private static func ensureArtifactsRoot() throws -> URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let root = cwd.appendingPathComponent(artifactsDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func resolveOutputURL(
        _ suppliedPath: String,
        artifactsRoot: URL,
        expectsDirectory: Bool
    ) -> URL {
        let expanded = (suppliedPath as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded, isDirectory: expectsDirectory)
        }
        return artifactsRoot.appendingPathComponent(expanded, isDirectory: expectsDirectory)
    }

    private static func resolveInputURL(_ suppliedPath: String) -> URL {
        let expanded = (suppliedPath as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return cwd.appendingPathComponent(expanded)
    }

    public static func run(arguments: [String]) async {
        var output = "output.wav"
        var voice = TtsConstants.recommendedVoice
        var metricsPath: String? = nil
        var text: String? = nil
        var deEss = true
        let backend: TtsBackend = .pocketTts
        var cloneVoicePath: String? = nil
        var voiceFilePath: String? = nil
        var saveVoicePath: String? = nil
        var pocketLanguage: PocketTtsLanguage = .english
        var pocketPlacement: PocketTtsModelPlacement = .gpu
        var pocketComputeUnits: PocketTtsComputeUnits = .default
        var pocketTemperature: Float = PocketTtsConstants.temperature
        // PocketTTS deterministic-seed mode (uses session API for fixed RNG).
        var pocketSeed: UInt64? = nil
        var i = 0
        while i < arguments.count {
            let argument = arguments[i]
            switch argument {
            case "--help", "-h":
                printUsage()
                return
            case "--output", "-o":
                if i + 1 < arguments.count {
                    output = arguments[i + 1]
                    i += 1
                }
            case "--voice", "-v":
                if i + 1 < arguments.count {
                    voice = arguments[i + 1]
                    i += 1
                }
            case "--metrics":
                if i + 1 < arguments.count {
                    metricsPath = arguments[i + 1]
                    i += 1
                }
            case "--backend":
                guard i + 1 < arguments.count,
                    ["pocket", "pockettts", "pocket-tts"].contains(arguments[i + 1].lowercased())
                else {
                    logger.error("This build includes only the PocketTTS backend")
                    exit(1)
                }
                i += 1
            case "--temperature":
                if i + 1 < arguments.count, let v = Float(arguments[i + 1]) {
                    pocketTemperature = v
                    i += 1
                }
            case "--seed":
                if i + 1 < arguments.count, let parsed = UInt64(arguments[i + 1]) {
                    pocketSeed = parsed
                    i += 1
                }
            case "--text":
                if i + 1 < arguments.count {
                    text = arguments[i + 1]
                    i += 1
                }
            case "--auto-download":
                // No-op: downloads are always ensured by the CLI. Accepted
                // for backward compatibility with documented examples.
                ()
            case "--no-deess":
                deEss = false
            case "--clone-voice":
                if i + 1 < arguments.count {
                    cloneVoicePath = arguments[i + 1]
                    i += 1
                }
            case "--voice-file":
                if i + 1 < arguments.count {
                    voiceFilePath = arguments[i + 1]
                    i += 1
                }
            case "--save-voice":
                if i + 1 < arguments.count {
                    saveVoicePath = arguments[i + 1]
                    i += 1
                }
            case "--compute-units":
                if i + 1 < arguments.count {
                    switch arguments[i + 1].lowercased() {
                    case "default": pocketComputeUnits = .default
                    case "no-ane", "avoid-ane": pocketComputeUnits = .avoidNeuralEngine
                    case "all": pocketComputeUnits = .uniform(.all)
                    case "cpu-gpu", "gpu": pocketComputeUnits = .uniform(.cpuAndGPU)
                    case "cpu-ane", "ane": pocketComputeUnits = .uniform(.cpuAndNeuralEngine)
                    case "cpu-only", "cpu": pocketComputeUnits = .uniform(.cpuOnly)
                    default:
                        logger.error(
                            "Unknown --compute-units '\(arguments[i + 1])'. Supported: default, no-ane, all, cpu-gpu, cpu-ane, cpu-only"
                        )
                        return
                    }
                    i += 1
                }
            case "--placement":
                if i + 1 < arguments.count {
                    let raw = arguments[i + 1].lowercased()
                    if let parsed = PocketTtsModelPlacement(rawValue: raw) {
                        pocketPlacement = parsed
                    } else {
                        logger.error(
                            "Unknown PocketTTS placement '\(arguments[i + 1])'. Supported: gpu, ane, ane-state"
                        )
                        return
                    }
                    i += 1
                }
            case "--language":
                if i + 1 < arguments.count {
                    let raw = arguments[i + 1].lowercased()
                    if let parsed = PocketTtsLanguage(rawValue: raw) {
                        pocketLanguage = parsed
                    } else {
                        let supported = PocketTtsLanguage.allCases
                            .map { $0.rawValue }
                            .joined(separator: ", ")
                        logger.error(
                            "Unknown PocketTTS language '\(arguments[i + 1])'. Supported: \(supported)"
                        )
                        return
                    }
                    i += 1
                }
            default:
                if text == nil {
                    text = argument
                } else {
                    logger.warning("Ignoring unexpected argument '\(argument)'")
                }
            }
            i += 1
        }

        guard let text = text else {
            printUsage()
            return
        }

        switch backend {
        case .pocketTts:
            await runPocketTts(
                text: text, output: output, voice: voice, deEss: deEss,
                metricsPath: metricsPath, cloneVoicePath: cloneVoicePath,
                voiceFilePath: voiceFilePath, saveVoicePath: saveVoicePath,
                language: pocketLanguage, seed: pocketSeed,
                placement: pocketPlacement, computeUnits: pocketComputeUnits,
                temperature: pocketTemperature)
        }
    }

    /// Run PocketTTS in deterministic-seed mode through the session API,
    /// applying the same de-essing post-processing as the non-seed path.
    private static func runPocketSeededSynthesis(
        manager: PocketTtsManager,
        text: String,
        voice: String,
        voiceData: PocketTtsVoiceData?,
        seed: UInt64,
        deEss: Bool,
        temperature: Float
    ) async throws -> Data {
        logger.info("PocketTTS deterministic mode: seed=\(seed)")
        let session = try await makePocketSeededSession(
            manager: manager, voice: voice, voiceData: voiceData, seed: seed,
            temperature: temperature)
        session.enqueue(text)
        session.finish()
        var allSamples: [Float] = []
        for try await frame in session.frames {
            allSamples.append(contentsOf: frame.samples)
        }
        if deEss {
            AudioPostProcessor.applyTtsPostProcessing(
                &allSamples,
                sampleRate: Float(PocketTtsConstants.audioSampleRate),
                deEssAmount: -3.0,
                smoothing: false)
        }
        return try AudioWAV.data(
            from: allSamples,
            sampleRate: Double(PocketTtsConstants.audioSampleRate))
    }

    /// Pick the right `makeSession` overload based on whether a custom
    /// `PocketTtsVoiceData` was supplied (cloned/loaded voice) or we should
    /// fall back to a named voice from the language pack.
    private static func makePocketSeededSession(
        manager: PocketTtsManager,
        voice: String,
        voiceData: PocketTtsVoiceData?,
        seed: UInt64,
        temperature: Float
    ) async throws -> PocketTtsSession {
        if let voiceData = voiceData {
            return try await manager.makeSession(
                voiceData: voiceData,
                temperature: temperature,
                seed: seed)
        }
        return try await manager.makeSession(
            voice: voice,
            temperature: temperature,
            seed: seed)
    }

    private static func runPocketTts(
        text: String, output: String, voice: String, deEss: Bool,
        metricsPath: String?, cloneVoicePath: String?,
        voiceFilePath: String?, saveVoicePath: String?,
        language: PocketTtsLanguage,
        seed: UInt64? = nil,
        placement: PocketTtsModelPlacement = .gpu,
        computeUnits: PocketTtsComputeUnits = .default,
        temperature: Float = PocketTtsConstants.temperature
    ) async {
        do {
            let tStart = Date()
            let pocketVoice =
                voice == TtsConstants.recommendedVoice
                ? PocketTtsConstants.defaultVoice : voice
            let manager = PocketTtsManager(
                defaultVoice: pocketVoice, language: language, placement: placement,
                computeUnits: computeUnits)
            logger.info(
                "PocketTTS language: \(language.rawValue), placement: \(placement.rawValue)")

            let tLoad0 = Date()
            try await manager.initialize()
            let tLoad1 = Date()

            // Handle voice cloning options
            var voiceData: PocketTtsVoiceData? = nil

            if let cloneVoicePath = cloneVoicePath {
                let cloneURL = resolveInputURL(cloneVoicePath)
                logger.info("Cloning voice from: \(cloneURL.path)")
                voiceData = try await manager.cloneVoice(from: cloneURL)
                logger.info("Voice cloned successfully")

                if let saveVoicePath = saveVoicePath {
                    let saveURL = resolveInputURL(saveVoicePath)
                    try manager.saveClonedVoice(voiceData!, to: saveURL)
                    logger.info("Saved cloned voice to: \(saveURL.path)")
                }
            } else if let voiceFilePath = voiceFilePath {
                let voiceURL = resolveInputURL(voiceFilePath)
                logger.info("Loading voice from: \(voiceURL.path)")
                voiceData = try manager.loadClonedVoice(from: voiceURL)
                logger.info("Voice loaded successfully")
            }

            let tSynth0 = Date()
            let wav: Data
            if let seed = seed {
                wav = try await runPocketSeededSynthesis(
                    manager: manager,
                    text: text,
                    voice: pocketVoice,
                    voiceData: voiceData,
                    seed: seed,
                    deEss: deEss,
                    temperature: temperature)
            } else if let voiceData = voiceData {
                wav = try await manager.synthesize(
                    text: text, voiceData: voiceData, temperature: temperature, deEss: deEss)
            } else {
                wav = try await manager.synthesize(
                    text: text, voice: pocketVoice, temperature: temperature, deEss: deEss)
            }
            let tSynth1 = Date()

            let outURL = resolveInputURL(output)
            try FileManager.default.createDirectory(
                at: outURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try wav.write(to: outURL)

            let loadS = tLoad1.timeIntervalSince(tLoad0)
            let synthS = tSynth1.timeIntervalSince(tSynth0)
            let totalS = tSynth1.timeIntervalSince(tStart)
            let sampleRate = Double(PocketTtsConstants.audioSampleRate)
            let payload = max(0, wav.count - 44)
            let audioSecs = Double(payload) / (sampleRate * 2.0)
            let rtfx = synthS > 0 ? audioSecs / synthS : 0

            logger.info("PocketTTS synthesis complete")
            logger.info("  Load: \(String(format: "%.3f", loadS))s")
            logger.info("  Synthesis: \(String(format: "%.3f", synthS))s")
            logger.info("  Audio: \(String(format: "%.3f", audioSecs))s")
            logger.info("  RTFx: \(String(format: "%.2f", rtfx))x")
            logger.info("  Total: \(String(format: "%.3f", totalS))s")
            logger.info("  Output: \(outURL.path)")

            // ASR round-trip evaluation
            if metricsPath != nil {
                logger.info("--- Running ASR for TTS→STT evaluation ---")
                var asrHypothesis: String? = nil
                var werValue: Double? = nil

                do {
                    let asrModels = try await AsrModels.downloadAndLoad()
                    let asr = AsrManager()
                    try await asr.loadModels(asrModels)

                    var decoderState = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
                    let transcription = try await asr.transcribe(outURL, decoderState: &decoderState)
                    asrHypothesis = transcription.text

                    let werMetrics = WERCalculator.calculateWERMetrics(
                        hypothesis: transcription.text, reference: text)
                    werValue = werMetrics.wer

                    logger.info("Reference:  \(text)")
                    logger.info("Hypothesis: \(transcription.text)")
                    logger.info(String(format: "WER: %.1f%%", werValue! * 100))

                    await asr.cleanup()
                } catch {
                    logger.warning("ASR evaluation failed: \(error.localizedDescription)")
                }

                if let metricsPath {
                    var metricsDict: [String: Any] = [
                        "backend": "pockettts",
                        "text": text,
                        "voice": pocketVoice,
                        "output": outURL.path,
                        "model_load_time_s": loadS,
                        "inference_time_s": synthS,
                        "audio_duration_s": audioSecs,
                        "realtime_speed": rtfx,
                        "total_time_s": totalS,
                    ]
                    if let asrHypothesis {
                        metricsDict["asr_hypothesis"] = asrHypothesis
                    }
                    if let werValue {
                        metricsDict["wer"] = werValue
                    }

                    let artifactsRoot = try ensureArtifactsRoot()
                    let mURL = resolveOutputURL(
                        metricsPath, artifactsRoot: artifactsRoot, expectsDirectory: false)
                    try FileManager.default.createDirectory(
                        at: mURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let json = try JSONSerialization.data(
                        withJSONObject: metricsDict, options: [.prettyPrinted])
                    try json.write(to: mURL)
                    logger.info("Metrics saved: \(mURL.path)")
                }
            }
        } catch {
            logger.error("PocketTTS Error: \(error)")
            print("PocketTTS failed: \(error)")
            exit(1)
        }
    }

    private static func printUsage() {
        print(
            """
            Usage: fluidaudio tts "text" [--output file.wav] [--voice alba] [--metrics metrics.json]

            Options:
              --output, -o         Output WAV path (default: output.wav)
              --voice, -v          Voice name (default: alba)
              --backend            pocket / pockettts / pocket-tts (the only backend in this build)
              --metrics            Write timing metrics to a JSON file (also runs ASR for evaluation)
              --no-deess           Disable de-essing (sibilance reduction, enabled by default)
              (models/dictionary auto-download is always on in CLI)
              --help, -h           Show this help

            Voice Cloning (PocketTTS only):
              --clone-voice FILE   Clone voice from audio file (WAV, MP3, M4A, etc.)
              --voice-file FILE    Load previously saved voice .bin file
              --save-voice FILE    Save cloned voice to .bin file for later use

            PocketTTS Language Packs:
              --language ID        Language pack (default: english)
                                   Supported: english, french_24l,
                                   german, german_24l, italian, italian_24l,
                                   portuguese, portuguese_24l, spanish, spanish_24l
                                   Note: French is 24-layer only (no 6-layer pack upstream)
              --seed N             Deterministic-mode seed (uses session API for fixed RNG)
              --temperature T      Generation temperature (default 0.7)
              --compute-units U    PocketTTS per-stage routing: default, no-ane (keep every
                                   stage off the Neural Engine, #881), all, cpu-gpu, cpu-ane, cpu-only
              --placement P        Model placement: gpu (default), ane (rank-4 ANE models),
                                   ane-state (Trial 23 MLState multifunction pipeline;
                                   macOS 15+/iOS 18+, requires pocket_state.mlmodelc)

            Voice Cloning examples:
              # Clone and synthesize in one step
              fluidaudio tts "Hello world" --backend pocket --clone-voice speaker.wav

              # Clone, save, and synthesize
              fluidaudio tts "Hello world" --backend pocket --clone-voice speaker.wav --save-voice my_voice.bin

              # Use previously saved voice
              fluidaudio tts "Hello world" --backend pocket --voice-file my_voice.bin
            """
        )
    }
}
