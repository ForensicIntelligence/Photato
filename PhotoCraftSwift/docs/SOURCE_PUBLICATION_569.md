# Source checkpoint 569

Native Swift 0.3.0, build 569, 18 November 2026. 32-bit RGB documents now convert to the default linear gray space using the measured source primaries. Promotion to 32 Bits/Channel uses the measured boundaries for fixed-point ICC gamma curves.

All 8,510,976 samples in 257 tested precision promotions and 194,560 samples in 38 RGB32-to-Gray32 cases match Photoshop on each architecture. All 661 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both signed macOS 14+ archive slices passed offscreen checks.

The grayscale comparison covers the default 32-bit gray destination with relative colorimetric intent, recognized standard RGB primaries, and custom linear RGB matrix profiles whose luminance weights sum to one. Other destination profiles, intents and custom white points still use ColorSync. Eight- and sixteen-bit grayscale conversion, transparent Multiply, and whole-file identity remain open.

[Development record](DEVLOG.md#dev-step-569) · [Validation data](HDR_GRAYSCALE_AND_GAMMA_569.json) · [Frozen source](SOURCE_SNAPSHOT_569.json)
