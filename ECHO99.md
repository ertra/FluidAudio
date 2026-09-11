# Echo99 dependency patch

This branch is based on upstream FluidAudio v0.15.7,
`41540ea237350afe5117a082b5c28eda642d0612`.

Echo99 uses PocketTTS, not LuxTTS. Both package manifests exclude `TTS/LuxTts`
from the library target, including its pronunciation resources. The LuxTTS model
registry entries, backend case, CLI routes, and CLI options are removed. The
LuxTTS CLI helper and tests are excluded from their respective targets. Upstream
LuxTTS files remain on disk to keep the patch small, but are not build inputs.

All other engines retain upstream behavior. Echo99 separately disables the
default `NemoTextProcessing` trait in its dependency declaration.

When updating, rebase this patch onto an identified upstream release and verify
the package source lists, the CLI build, model registry tests, and Echo99's
universal Release build. Echo99's `tools/check-no-luxtts.sh` rejects executables
or bundles that reintroduce LuxTTS.
