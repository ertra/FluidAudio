#if os(macOS)
import CoreML
import FluidAudio
import Foundation

/// `fluidaudio tts-benchmark` — quantitative TTS benchmark harness.
///
/// Reports **TTFT / cold-start / warm-start latency, per-stage timings,
/// peak RSS, WER + CER per category** — i.e. the things conversational
/// TTS users actually feel — instead of just RTFx.
///
/// Backends:
///   pocket-tts    — streaming flow-matching (no per-stage timings)
///
/// Usage:
///   fluidaudio tts-benchmark --backend pocket-tts \
///       --corpus minimax-english \
///       --voice alba \
///       --compute-units default \
///       --output-json bench.json
///
/// Corpora land in `Benchmarks/tts/corpus/minimax/<lang>.txt` —
/// the MiniMax Multilingual TTS Test Set (CC-BY-SA-4.0,
/// 24 languages × 100 phrases). The `.txt` files are gitignored;
/// populate them with `swift run fluidaudio minimax-corpus`. See
/// `Documentation/TTS/MinimaxCorpus.md` for attribution + reproduction
/// notes and `Documentation/TTS/Benchmarks.md` for the per-backend ↔
/// language coverage matrix. Reference with `--corpus minimax-<lang>`
/// (e.g. `minimax-english`, `minimax-chinese`, `minimax-vietnamese`, …).
public enum TtsBenchmarkCommand {

    private static let logger = AppLogger(category: "TtsBenchmarkCommand")

    // MARK: - Per-phrase sample emitted by every backend driver.
    private struct BackendPhraseSample {
        let synthMs: Double
        let ttftMs: Double  // For one-shot backends, == synthMs.
        let samples: [Float]
        let sampleRate: Int
        let stageMs: [String: Double]  // Empty if backend has no per-stage timings.
        let extraFields: [String: Any]  // encoder_tokens, finished_on_eos, etc.
    }

    // MARK: - ASR backend selection
    //
    // The TTS→ASR roundtrip uses Parakeet TDT (English-only, auto-downloaded).
    // Echo99 build: the Cohere Transcribe backend is excluded with its engine.
    fileprivate enum AsrChoice {
        case skip
        case parakeet

        var label: String {
            switch self {
            case .skip: return "skip"
            case .parakeet: return "parakeet-tdt"
            }
        }

        var skipped: Bool {
            if case .skip = self { return true } else { return false }
        }
    }

    /// Closure-based ASR adapter so `runPhraseLoop` doesn't have to know
    /// which backend it's driving. Built once before the per-phrase loop,
    /// torn down after.
    fileprivate struct AsrLoop {
        let label: String
        let transcribeOne: (URL) async throws -> String
        let cleanup: () async -> Void
    }

    public static func run(arguments: [String]) async {
        var backendName = "pocket-tts"
        var corpusName: String?
        var corpusPath: String?
        var voice: String?
        var languageName: String?
        var computeUnitsName = "default"
        var outputJson: String?
        var audioDir: String?
        var skipAsr = false
        var asrBackendName: String?

        var i = 0
        while i < arguments.count {
            let arg = arguments[i]
            switch arg {
            case "--backend":
                if i + 1 < arguments.count {
                    backendName = arguments[i + 1]
                    i += 1
                }
            case "--corpus":
                if i + 1 < arguments.count {
                    corpusName = arguments[i + 1]
                    i += 1
                }
            case "--corpus-path":
                if i + 1 < arguments.count {
                    corpusPath = arguments[i + 1]
                    i += 1
                }
            case "--voice":
                if i + 1 < arguments.count {
                    voice = arguments[i + 1]
                    i += 1
                }
            case "--language":
                if i + 1 < arguments.count {
                    languageName = arguments[i + 1]
                    i += 1
                }
            case "--compute-units":
                if i + 1 < arguments.count {
                    computeUnitsName = arguments[i + 1]
                    i += 1
                }
            case "--output-json":
                if i + 1 < arguments.count {
                    outputJson = arguments[i + 1]
                    i += 1
                }
            case "--audio-dir":
                if i + 1 < arguments.count {
                    audioDir = arguments[i + 1]
                    i += 1
                }
            case "--skip-asr":
                skipAsr = true
            case "--asr-backend":
                if i + 1 < arguments.count {
                    asrBackendName = arguments[i + 1]
                    i += 1
                }
            case "--help", "-h":
                printUsage()
                return
            default:
                logger.warning("Unknown argument: \(arg)")
            }
            i += 1
        }

        let backend = parseBackend(backendName)

        // Resolve corpus.
        var phrases: [(category: String, text: String)]
        let corpusLabel: String
        do {
            if let corpusPath {
                let url = resolveURL(corpusPath, isDirectory: false)
                let raw = try String(contentsOf: url, encoding: .utf8)
                phrases = parseCorpus(raw, category: url.deletingPathExtension().lastPathComponent)
                corpusLabel = url.lastPathComponent
            } else {
                let resolved = corpusName ?? backend.defaultCorpus
                phrases = try loadShippedCorpus(resolved)
                corpusLabel = resolved
            }
        } catch {
            logger.error("Failed to load corpus: \(error.localizedDescription)")
            exit(1)
        }
        guard !phrases.isEmpty else {
            logger.error("Corpus is empty after parsing")
            exit(1)
        }

        logger.info("Loaded \(phrases.count) phrase(s) from corpus '\(corpusLabel)'")

        guard let preset = TtsComputeUnitPreset(cliValue: computeUnitsName) else {
            logger.error(
                "Unknown --compute-units value: \(computeUnitsName). Expected default | all-ane | cpu-and-gpu | cpu-only | ane-tail-gpu."
            )
            exit(1)
        }

        // Resolve ASR backend choice. Precedence:
        //   --skip-asr or --asr-backend none → .skip
        //   --asr-backend parakeet           → .parakeet
        //   no flag, otherwise               → .parakeet
        let asrChoice: AsrChoice
        do {
            asrChoice = try await resolveAsrChoice(
                skipAsrFlag: skipAsr,
                backendName: asrBackendName,
                ttsBackend: backend)
        } catch {
            logger.error("Failed to resolve ASR backend: \(error.localizedDescription)")
            exit(1)
        }
        logger.info("ASR backend: \(asrChoice.label)")

        do {
            switch backend {
            case .pocketTts:
                try await runPocketTts(
                    phrases: phrases, corpusLabel: corpusLabel,
                    voice: voice ?? PocketTtsConstants.defaultVoice,
                    languageName: languageName,
                    preset: preset, outputJson: outputJson, audioDir: audioDir,
                    asrChoice: asrChoice)
            }
        } catch {
            logger.error("tts-benchmark failed: \(error)")
            exit(1)
        }
    }

    // MARK: - PocketTTS driver

    private static func runPocketTts(
        phrases: [(category: String, text: String)],
        corpusLabel: String,
        voice: String,
        languageName: String?,
        preset: TtsComputeUnitPreset,
        outputJson: String?,
        audioDir: String?,
        asrChoice: AsrChoice
    ) async throws {
        if preset != .default {
            logger.warning(
                "PocketTTS does not expose per-call compute-unit overrides; --compute-units \(preset.cliValue) ignored."
            )
        }
        let language = parsePocketLanguage(languageName)
        logger.info("PocketTTS language: \(language.rawValue)")

        let manager = PocketTtsManager(defaultVoice: voice, language: language)

        let coldStart = Date()
        try await manager.initialize()
        let coldStartS = Date().timeIntervalSince(coldStart)
        logger.info(String(format: "Cold start (initialize): %.2fs", coldStartS))

        let firstStart = Date()
        var firstFrameMs: Double = 0
        var firstFrameCount = 0
        let warmupStream = try await manager.synthesizeStreaming(
            text: "Initialization warm-up.", voice: voice)
        for try await frame in warmupStream {
            if firstFrameCount == 0 {
                firstFrameMs = Date().timeIntervalSince(firstStart) * 1000
            }
            firstFrameCount += 1
            _ = frame.samples
        }
        let firstSynthMs = Date().timeIntervalSince(firstStart) * 1000
        logger.info(
            String(
                format: "First synth: %.0f ms total, %.0f ms TTFT (frames=%d)",
                firstSynthMs, firstFrameMs, firstFrameCount))

        try await runPhraseLoop(
            backendId: "pocket-tts",
            voiceLabel: voice,
            corpusLabel: corpusLabel,
            phrases: phrases,
            preset: preset,
            coldStartS: coldStartS,
            firstSynthMs: firstSynthMs,
            outputJson: outputJson,
            audioDir: audioDir,
            asrChoice: asrChoice,
            normalizeWavs: true,
            extraSummary: ["voice": voice, "language": language.rawValue]
        ) { text in
            // PocketTTS is streaming-first: we measure TTFT (time to first
            // audio frame) separately from total synth time so the benchmark
            // numbers reflect what a streaming consumer actually experiences.
            let t0 = Date()
            let stream = try await manager.synthesizeStreaming(text: text, voice: voice)
            var aggregated: [Float] = []
            var ttftMs: Double = 0
            var frameCount = 0
            var lastChunkCount = 0
            for try await frame in stream {
                if frameCount == 0 {
                    ttftMs = Date().timeIntervalSince(t0) * 1000
                }
                aggregated.append(contentsOf: frame.samples)
                frameCount += 1
                lastChunkCount = frame.chunkCount
            }
            let synthMs = Date().timeIntervalSince(t0) * 1000
            return BackendPhraseSample(
                synthMs: synthMs,
                ttftMs: ttftMs,
                samples: aggregated,
                sampleRate: PocketTtsConstants.audioSampleRate,
                stageMs: [:],
                extraFields: [
                    "frame_count": frameCount,
                    "chunk_count": lastChunkCount,
                ]
            )
        }
    }

    // MARK: - Shared per-phrase loop + summary

    private static func runPhraseLoop(
        backendId: String,
        voiceLabel: String,
        corpusLabel: String,
        phrases: [(category: String, text: String)],
        preset: TtsComputeUnitPreset,
        coldStartS: Double,
        firstSynthMs: Double,
        outputJson: String?,
        audioDir: String?,
        asrChoice: AsrChoice,
        normalizeWavs: Bool,
        extraSummary: [String: Any],
        synthOne: (String) async throws -> BackendPhraseSample
    ) async throws {
        // Optional output dir for WAVs.
        var audioDirURL: URL? = nil
        if let audioDir {
            let url = resolveURL(audioDir, isDirectory: true)
            try FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: true)
            audioDirURL = url
        }

        // Build optional ASR backend (Parakeet or none).
        let asrLoop = try await buildAsrLoop(asrChoice)

        var perPhrase: [[String: Any]] = []
        var byCategory: [String: [Int]] = [:]

        for (idx, item) in phrases.enumerated() {
            let label = String(format: "[%02d/%02d]", idx + 1, phrases.count)
            logger.info("\(label) [\(item.category)] \(item.text)")

            let sample = try await synthOne(item.text)
            let audioMs =
                Double(sample.samples.count) / Double(sample.sampleRate) * 1000
            let rtfx = sample.synthMs > 0 ? audioMs / sample.synthMs : 0

            // Persist WAV (audioDir if set, else temp file for ASR).
            let wavURL: URL
            if let audioDirURL {
                wavURL = audioDirURL.appendingPathComponent(
                    String(format: "phrase_%03d.wav", idx + 1))
            } else {
                wavURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("tts-benchmark-\(UUID().uuidString).wav")
            }
            let wavData = try AudioWAV.data(
                from: sample.samples, sampleRate: Double(sample.sampleRate),
                normalize: normalizeWavs)
            try wavData.write(to: wavURL)

            var werValue = Double.nan
            var cerValue = Double.nan
            var hypothesis = ""
            var asrMs = 0.0
            if let asrLoop {
                let asr0 = Date()
                hypothesis = try await asrLoop.transcribeOne(wavURL)
                asrMs = Date().timeIntervalSince(asr0) * 1000
                let m = WERCalculator.calculateWERAndCER(
                    hypothesis: hypothesis, reference: item.text)
                werValue = m.wer
                cerValue = m.cer
            }

            if audioDirURL == nil {
                try? FileManager.default.removeItem(at: wavURL)
            }

            logger.info(
                String(
                    format:
                        "  ttft=%.0f ms  synth=%.0f ms  audio=%.0f ms  rtfx=%.2fx  wer=%.1f%%  cer=%.1f%%",
                    sample.ttftMs, sample.synthMs, audioMs, rtfx,
                    werValue.isNaN ? 0 : werValue * 100,
                    cerValue.isNaN ? 0 : cerValue * 100))

            byCategory[item.category, default: []].append(perPhrase.count)
            var phraseDict: [String: Any] = [
                "index": idx + 1,
                "category": item.category,
                "reference": item.text,
                "hypothesis": hypothesis,
                "ttft_ms": sample.ttftMs,
                "synth_ms": sample.synthMs,
                "audio_ms": audioMs,
                "rtfx": rtfx,
                "wer": werValue.isNaN ? NSNull() : werValue as Any,
                "cer": cerValue.isNaN ? NSNull() : cerValue as Any,
                "asr_ms": asrMs,
                "stage_ms": sample.stageMs,
                "wav_path": audioDirURL == nil ? "" : wavURL.path,
            ]
            for (k, v) in sample.extraFields {
                phraseDict[k] = v
            }
            perPhrase.append(phraseDict)
        }

        if let asrLoop {
            await asrLoop.cleanup()
        }

        // Aggregate.
        let totalSynthMs = perPhrase.reduce(0.0) { $0 + ($1["synth_ms"] as? Double ?? 0) }
        let totalAudioMs = perPhrase.reduce(0.0) { $0 + ($1["audio_ms"] as? Double ?? 0) }
        let aggRtfx = totalSynthMs > 0 ? totalAudioMs / totalSynthMs : 0

        let synthMsValues = perPhrase.compactMap { $0["synth_ms"] as? Double }.sorted()
        let p50 = percentile(synthMsValues, 0.5)
        let p95 = percentile(synthMsValues, 0.95)
        let ttftValues = perPhrase.compactMap { $0["ttft_ms"] as? Double }.sorted()
        let ttftP50 = percentile(ttftValues, 0.5)
        let ttftP95 = percentile(ttftValues, 0.95)

        var categories: [[String: Any]] = []
        for (cat, indexes) in byCategory.sorted(by: { $0.key < $1.key }) {
            let werVals = indexes.compactMap { perPhrase[$0]["wer"] as? Double }
            let cerVals = indexes.compactMap { perPhrase[$0]["cer"] as? Double }
            let synthVals = indexes.compactMap { perPhrase[$0]["synth_ms"] as? Double }
            let audioVals = indexes.compactMap { perPhrase[$0]["audio_ms"] as? Double }
            let synthSum = synthVals.reduce(0, +)
            let audioSum = audioVals.reduce(0, +)
            let macroWer =
                werVals.isEmpty ? Double.nan : werVals.reduce(0, +) / Double(werVals.count)
            let macroCer =
                cerVals.isEmpty ? Double.nan : cerVals.reduce(0, +) / Double(cerVals.count)
            categories.append([
                "category": cat,
                "phrase_count": indexes.count,
                "macro_wer": macroWer.isNaN ? NSNull() : macroWer as Any,
                "macro_cer": macroCer.isNaN ? NSNull() : macroCer as Any,
                "synth_ms_p50": percentile(synthVals.sorted(), 0.5),
                "synth_ms_p95": percentile(synthVals.sorted(), 0.95),
                "rtfx": synthSum > 0 ? audioSum / synthSum : 0,
            ])
        }

        let peakRssMb =
            Double(FluidAudioCLI.fetchPeakMemoryUsageBytes() ?? 0) / 1024 / 1024

        // Banner.
        logger.info("--- Summary ---")
        logger.info("  backend:        \(backendId)")
        logger.info("  voice/speaker:  \(voiceLabel)")
        logger.info("  corpus:         \(corpusLabel) (n=\(phrases.count))")
        logger.info("  compute units:  \(preset.cliValue)")
        logger.info(String(format: "  cold start:     %.2fs", coldStartS))
        logger.info(String(format: "  first synth:    %.0f ms", firstSynthMs))
        logger.info(String(format: "  TTFT p50/p95:   %.0f / %.0f ms", ttftP50, ttftP95))
        logger.info(String(format: "  warm synth p50: %.0f ms", p50))
        logger.info(String(format: "  warm synth p95: %.0f ms", p95))
        logger.info(String(format: "  agg RTFx:       %.2fx", aggRtfx))
        logger.info(String(format: "  peak RSS:       %.0f MB", peakRssMb))
        if !asrChoice.skipped {
            let werVals = perPhrase.compactMap { $0["wer"] as? Double }
            let cerVals = perPhrase.compactMap { $0["cer"] as? Double }
            let macroWer =
                werVals.isEmpty ? 0 : werVals.reduce(0, +) / Double(werVals.count)
            let macroCer =
                cerVals.isEmpty ? 0 : cerVals.reduce(0, +) / Double(cerVals.count)
            logger.info("  ASR backend:    \(asrChoice.label)")
            logger.info(String(format: "  macro WER:      %.2f%%", macroWer * 100))
            logger.info(String(format: "  macro CER:      %.2f%%", macroCer * 100))
        } else {
            logger.info("  WER/CER:        skipped")
        }

        if let outputJson {
            var summary: [String: Any] = [
                "backend": backendId,
                "corpus": corpusLabel,
                "phrase_count": phrases.count,
                "compute_units": preset.cliValue,
                "cold_start_s": coldStartS,
                "first_synth_ms": firstSynthMs,
                "ttft_ms_p50": ttftP50,
                "ttft_ms_p95": ttftP95,
                "warm_synth_ms_p50": p50,
                "warm_synth_ms_p95": p95,
                "agg_rtfx": aggRtfx,
                "peak_rss_mb": peakRssMb,
                "asr_skipped": asrChoice.skipped,
                "asr_backend": asrChoice.label,
            ]
            for (k, v) in extraSummary {
                summary[k] = v
            }
            let report: [String: Any] = [
                "summary": summary,
                "categories": categories,
                "phrases": perPhrase,
            ]
            let url = resolveURL(outputJson, isDirectory: false)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let data = try JSONSerialization.data(
                withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url)
            logger.info("Report written: \(url.path)")
        }
    }

    // MARK: - Corpus loading

    private static func loadShippedCorpus(
        _ name: String
    ) throws -> [(category: String, text: String)] {
        let cwd = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let relativePath = corpusRelativePath(for: name)
        let url = cwd.appendingPathComponent(relativePath, isDirectory: false)
        let raw = try String(contentsOf: url, encoding: .utf8)
        return parseCorpus(raw, category: name)
    }

    /// Map a `--corpus` name to its on-disk relative path.
    ///
    /// All shipped corpora are MiniMax Multilingual TTS Test Set
    /// languages — `minimax-<lang>` resolves to
    /// `Benchmarks/tts/corpus/minimax/<lang>.txt`. The CC-BY-SA-4.0
    /// attribution lives next to the data in `minimax/README.md`.
    /// Pass `--corpus-path` for ad-hoc files outside the shipped set.
    private static func corpusRelativePath(for name: String) -> String {
        let prefix = "minimax-"
        if name.hasPrefix(prefix) {
            let lang = String(name.dropFirst(prefix.count))
            return "Benchmarks/tts/corpus/minimax/\(lang).txt"
        }
        // Back-compat shim — anything else is assumed to live next to
        // the minimax subdirectory. Prefer `--corpus-path` for non-shipped
        // corpora.
        return "Benchmarks/tts/corpus/\(name).txt"
    }

    private static func parseCorpus(
        _ raw: String, category: String
    ) -> [(category: String, text: String)] {
        return
            raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { (category: category, text: $0) }
    }

    // MARK: - Backend dispatch

    private enum Backend: String {
        case pocketTts

        var defaultCorpus: String {
            return "minimax-english"
        }
    }

    private static func parseBackend(_ name: String) -> Backend {
        guard ["pocket-tts", "pockettts", "pocket"].contains(name.lowercased()) else {
            logger.error("This build includes only the PocketTTS backend")
            exit(1)
        }
        return .pocketTts
    }

    private static func parsePocketLanguage(_ name: String?) -> PocketTtsLanguage {
        guard let name, let l = PocketTtsLanguage(rawValue: name.lowercased()) else {
            return .english
        }
        return l
    }

    // MARK: - Helpers

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let idx = Int((Double(sorted.count - 1) * p).rounded())
        return sorted[max(0, min(sorted.count - 1, idx))]
    }

    private static func resolveURL(_ path: String, isDirectory: Bool) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded, isDirectory: isDirectory)
        }
        let cwd = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return cwd.appendingPathComponent(expanded, isDirectory: isDirectory)
    }

    // MARK: - ASR backend resolution & adapter construction

    /// Map CLI flags + TTS backend defaults to a concrete `AsrChoice`.
    ///
    /// Precedence: `--skip-asr` and `--asr-backend none` always win. With
    /// no flag, defaults to Parakeet TDT (English-only).
    private static func resolveAsrChoice(
        skipAsrFlag: Bool,
        backendName: String?,
        ttsBackend: Backend
    ) async throws -> AsrChoice {
        let normalized = backendName?.lowercased()
        if skipAsrFlag || normalized == "none" {
            return .skip
        }
        switch normalized {
        case "parakeet":
            return .parakeet
        case nil:
            return .parakeet
        default:
            logger.warning(
                "Unknown --asr-backend value '\(normalized ?? "")', falling back to parakeet.")
            return .parakeet
        }
    }

    /// Build the per-phrase ASR adapter for a resolved choice. Returns
    /// `nil` for `.skip` so the loop can short-circuit.
    private static func buildAsrLoop(_ choice: AsrChoice) async throws -> AsrLoop? {
        switch choice {
        case .skip:
            return nil
        case .parakeet:
            let asrModels = try await AsrModels.downloadAndLoad()
            let asr = AsrManager()
            try await asr.loadModels(asrModels)
            let layers = await asr.decoderLayerCount
            return AsrLoop(
                label: "parakeet-tdt",
                transcribeOne: { url in
                    var state = TdtDecoderState.make(decoderLayers: layers)
                    let r = try await asr.transcribe(url, decoderState: &state)
                    return r.text
                },
                cleanup: { await asr.cleanup() }
            )
        }
    }

    private static func printUsage() {
        logger.info(
            """
            Usage: fluidaudio tts-benchmark [options]

            Benchmark PocketTTS latency, peak RSS, WER and CER.
              --backend <name>          pocket-tts (the only backend in this build)
              --corpus <name>           MiniMax corpus: minimax-<language>
              --corpus-path <path>      Custom corpus file
              --voice <name>            PocketTTS voice
              --language <code>         PocketTTS language pack
              --compute-units <preset>  default | all-ane | cpu-and-gpu | cpu-only
              --output-json <path>      JSON report
              --audio-dir <path>        Keep generated WAV files
              --skip-asr                Skip ASR roundtrip
              --asr-backend <name>      parakeet | none
              --help, -h                Show help

            Example:
              fluidaudio tts-benchmark --backend pocket-tts --corpus minimax-german --language german
            """
        )
    }

}
#endif
