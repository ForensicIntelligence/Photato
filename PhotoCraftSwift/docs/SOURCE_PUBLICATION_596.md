# Source checkpoint 596

Native Swift 0.3.0, build 596, 19 November 2026. Wide Feather reuses source row bands for vector, pixel and Smart Filter masks.

The 1,000 px vector viewport went from 1.343 s to 0.995 s on Apple Silicon. The oversize Smart Filter mask control went from 1.483 s to 0.862 s. These are medians of three alternating runs on the same host. All 1,155 sampled Float32 coverage or output words matched build 595 bit for bit on each architecture across eight vector, raster and Smart Filter cases. The regression suite also passed the saved Photoshop wide pixel-mask references.

All 908 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both slices of the extracted universal package launched offscreen and declare macOS 14 as the minimum. Full-canvas performance, live editing cadence, physical Intel and macOS 14 runtime checks, and Photoshop byte parity remain open.

[Development record](DEVLOG.md#dev-step-596) · [Validation data](WIDE_FEATHER_BANDS_596.json).
