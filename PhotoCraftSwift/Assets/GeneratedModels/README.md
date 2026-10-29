# Optional native person feature model

Run `python3 scripts/prepare-people-model.py` from the native project root. This downloads the pinned Google MediaPipe multiclass model into a build cache, reconstructs its operators as Core ML, compares outputs to the original model, and compiles an optional resource here. Python/TensorFlow/TFLite are development tools only; the app uses Swift and Apple Core ML.

Generated weights are ignored by source control and must not be added to a source PR. Both command-line packaging and Xcode copy the model when present. Without it, whole-person selection remains available and semantic parts are explicitly unavailable. The original model card specifies Apache2.0 and warns that masks are not pixel-perfect. See `docs/PEOPLE_FEATURE_REFERENCES.json` for provenance and validation limits.
