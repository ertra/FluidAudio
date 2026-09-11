# Echo99 dependency patch

This branch is based on upstream FluidAudio v0.15.7,
`41540ea237350afe5117a082b5c28eda642d0612`.

Echo99 uses PocketTTS, not LuxTTS. Both package manifests exclude `TTS/LuxTts`
from the library target, including its pronunciation resources. The LuxTTS model
registry entries, backend case, CLI routes, and CLI options are removed. The
LuxTTS CLI helper and tests are excluded from their respective targets. Upstream
LuxTTS files remain on disk to keep the patch small, but are not build inputs.

Both manifests also remove the `NemoTextProcessing` binary target, its dependency,
and its trait. The existing `canImport(CNemoTextProcessing)` guards select the
no-engine normalization paths, matching Echo99's previous `traits: []` behavior.
PocketTTS normalizes its own text. Echo99 can now link this package directly;
it no longer needs a wrapper package to disable the NeMo trait in Xcode.

When updating, rebase this patch onto an identified upstream release and verify
the package source lists, the CLI build, model registry tests, and Echo99's
universal Release build. Echo99's `tools/check-no-luxtts.sh` rejects executables
or bundles that reintroduce LuxTTS; `tools/check-no-nemo.sh` checks both Mac
architectures and rejects retained NeMo/Rust fingerprints.
