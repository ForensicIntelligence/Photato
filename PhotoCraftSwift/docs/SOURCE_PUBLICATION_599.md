# Source checkpoint 599

Native Swift 0.3.0, build 599, 19 November 2026. Wide rectangular vector masks reuse filtered windows across the canvas.

The 300,000 × 300,000 stress case with an inverted 1,000 px Feather mask completed in 35.71 s on Apple Silicon and 49.08 s under Rosetta. Build 598 exceeded the 200-second cutoff on Apple Silicon. The new whole-canvas output matched all 11,560 sampled Float32 words of the previous viewport output on each architecture.

The 37.8 MP RGB32 control at 110.25 px went from 2.220 s to 1.358 s on Apple Silicon and from 3.605 s to 2.625 s under Rosetta. Each value is the median of three alternating runs. The two builds matched all 11,560 sampled Float32 words on each architecture.

The Apple Silicon viewport control with an aligned 1,000 px edge went from 0.145 s to 0.013 s. All 1,260 sampled words per architecture matched across the nine viewport controls, which include curved vector masks, pixel masks and a Smart Filter mask.

All 914 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both extracted universal app slices passed signature and offscreen launch checks and declare macOS 14 as the minimum.

The live Photoshop session returned AppleEvent error −1712. Fresh Photoshop wide-mask comparisons, broader vector geometry, the RGB32 bottom-layer opacity proof, physical Intel and macOS 14 runtime checks, and full Photoshop byte parity remain open.

[Development record](DEVLOG.md#dev-step-599) · [Validation data](WIDE_RECTANGLE_WINDOWS_599.json).
