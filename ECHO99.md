# Echo99 dependency patch

This branch is based on upstream FluidAudio v0.18.0,
`b6a8b3916892ac92597526222f6b04f26c01efb6`.

Echo99 uses PocketTTS. Both package manifests exclude the unused LuxTTS,
KokoroAne, StyleTTS2, Supertonic3, NeuTts, Inflect, Chatterbox, and Paradee implementations from the
library target. LuxTTS pronunciation resources are also excluded. Their model
registry entries, backend cases, CLI branches/options, and engine-specific tests
are removed from the build. The Kokoro-only TTS-to-ASR CLI command is excluded;
the PocketTTS CLI and benchmark remain available.

Upstream engine files remain on disk to keep the patch small, but are not build
inputs. Shared TTS helpers, PocketTTS, ASR, diarization, and VAD implementations
are preserved. The generic Kokoro-hosted G2P assets remain available to the shared
phonemizer; they do not include a Kokoro synthesis engine.

Both manifests also remove the `NemoTextProcessing` binary target, its dependency,
and its trait. The existing `canImport(CNemoTextProcessing)` guards select the
no-engine normalization paths, matching Echo99's previous `traits: []` behavior.
PocketTTS normalizes its own text. Echo99 can now link this package directly;
it no longer needs a wrapper package to disable the NeMo trait in Xcode.

When updating, rebase this patch onto an identified upstream release and verify
the package source lists, the CLI build, model registry tests, and Echo99's
universal Release build. Echo99's `tools/check-no-unused-tts.sh` rejects executables
or bundles that reintroduce unused TTS backends; `tools/check-no-nemo.sh` checks both Mac
architectures and rejects retained NeMo/Rust fingerprints.

Paradee (new in 0.17.7) is excluded with the other engines: it reuses KokoroAne's
English frontend, so it cannot build once KokoroAne is excluded. The LocalVQE
speech-enhancement module (new in 0.17.5) is not a TTS engine, ships no resources, and
stays in the build; Echo99 does not call it.

New in 0.18: PocketTTS's small models and the Gradium Phonon normalizer
(`TTS/PocketTTS/Small`, `TTS/PocketTTS/Phonon`) are excluded too: Echo99 runs the
original PocketTTS models only. Their constants in `ModelNames.PocketTts` stay, because
upstream keys them outside the engine. The `LuxTtsG2pResources` target is removed (its
one consumer is excluded). Upstream's opt-out `TTS` and `Diarizer` traits are replaced by
plain `.define`s in both manifests: Echo99 uses both subsystems, and the two manifests
are now identical apart from the tools version.
