# Optional native person feature model

Run `python3 scripts/prepare-people-model.py` from the native project root. This downloads the pinned Google MediaPipe multiclass model into a build cache, reconstructs its operators as Core ML, compares outputs to the original model, and compiles an optional resource here. Python/TensorFlow/TFLite are development tools only; the app uses Swift and Apple Core ML.

Generated weights are ignored by source control and must not be added to a source PR. Both command-line packaging and Xcode copy the model when present. Without it, whole-person selection remains available and semantic parts are explicitly unavailable. The original model card specifies Apache2.0 and warns that masks are not pixel-perfect. See `docs/PEOPLE_FEATURE_REFERENCES.json` for provenance and validation limits.


## Local super-resolution

Run `python3 scripts/prepare-upscale-model.py` from the project root to acquire the pinned 2.2 MB BSD-3 Real-ESRGAN Core ML package and compile it with Xcode. Existing generated resources are verified and not overwritten. The SHA-256, upstream conversion revision and five compiled input hashes are retained in LocalUpscale.provenance.json. Ordinary source builds may omit this optional model; the native dialog explains that it is unavailable. Inference is Swift/Core ML on the local Mac, without Python, a server or runtime download. See LICENSE-RealESRGAN and ATTRIBUTION.md. Core editing remains macOS 14+; this provider currently requires macOS 26+ Apple Silicon.
