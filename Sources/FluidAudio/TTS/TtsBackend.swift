#if TTS
import Foundation

/// Synthesis backend included in the Echo99 dependency build.
public enum TtsBackend: Sendable {
    /// PocketTTS — flow-matching language model, autoregressive streaming synthesis.
    case pocketTts
}
#endif
