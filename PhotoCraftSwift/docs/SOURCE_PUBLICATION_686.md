# Source checkpoint 686

Native Swift 0.3.0, build 686, 2026-11-20.

Legacy RGB8 shape patterns now use rounded half-size tiles and quantized corner interpolation in supported cases.

All 351 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both signed macOS 14+ preview slices launched offscreen.

At 25%, 50%, 56%, and 200% the regenerated layer colors matched all 9,309 sampled opaque interior pixels per case. Four other pattern-placement cases matched the same number of pixels each. The edited and untouched exports were byte-identical across build configurations. The native saves and both Photoshop formats reopened with editable patterns.

The comparisons cover the authored tiles and placements. Rotated and transparent tiles, odd-size reductions, other depths, and full shape-edge output still require comparison. Preparing a synthetic 4,000 × 4,000 sparse tile at 25% took 0.75 seconds on this test Mac. Live Photoshop 2026 reopen remains unverified.

[Development record](LEGACY_PATTERN_SCALING_686.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_686.json)
