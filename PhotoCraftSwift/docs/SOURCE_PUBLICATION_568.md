# Source checkpoint 568

Native Swift 0.3.0, build 568, 18 November 2026. RGB and grayscale gamma 0.5 profiles now promote to 32 Bits/Channel using the measured rounding on each architecture. PSD and PSB use native gray samples for supported 32-bit layer stacks.

All 2,142,336 stored samples from 59 tested conversion cases match the corresponding Photoshop files on each architecture. Five Gray32 layer stacks match all 960 merged words under each of four compression modes in PSD and PSB. All 657 selected tests passed in Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both signed macOS 14+ archive slices passed offscreen checks.

The Gray32 comparison covers aligned, full-canvas raster stacks using Normal or Multiply over an opaque base. It includes an ordinary pixel mask, partial layer opacity, and transparent Normal. Cross-mode conversion, transparent Multiply, other blend modes, transformed stacks, and whole-file identity remain open.

[Development record](DEVLOG.md#dev-step-568) · [Validation data](GRAY32_AND_HALF_GAMMA_568.json) · [Frozen source](SOURCE_SNAPSHOT_568.json)
