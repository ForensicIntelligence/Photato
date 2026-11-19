# Source checkpoint 597

Native Swift 0.3.0, build 597, 19 November 2026. Wide Feather reuses the second filter pass’s window sums when they fit a bounded cache.

The 1,000 px vector viewport went from 1.001 s to 0.933 s on Apple Silicon. The RGB32 pixel-mask control went from 0.180 s to 0.135 s and the oversize Smart Filter mask from 0.867 s to 0.821 s. These are medians of three alternating runs on the same host. All 1,155 sampled Float32 coverage or output words matched build 596 bit for bit on each architecture across eight vector, raster and Smart Filter cases. The regression suite also passed the saved Photoshop wide pixel-mask references.

All 909 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both slices of the extracted universal package launched offscreen and declare macOS 14 as the minimum. Full-canvas performance, live editing cadence, physical Intel and macOS 14 runtime checks, and Photoshop byte parity remain open.

[Development record](DEVLOG.md#dev-step-597) · [Validation data](WIDE_FEATHER_REPLAY_597.json).
