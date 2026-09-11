# Echo99 dependency patch

This branch is based on upstream FluidAudio v0.15.7,
`41540ea237350afe5117a082b5c28eda642d0612`.

Echo99 uses PocketTTS. Both package manifests exclude the unused LuxTTS,
KokoroAne, StyleTTS2, Supertonic3, NeuTts, and Inflect implementations from the
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
