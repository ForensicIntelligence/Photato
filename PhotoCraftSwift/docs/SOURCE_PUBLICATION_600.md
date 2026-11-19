# Source checkpoint 600

Native Swift 0.3.0, build 600, 19 November 2026. Large RGB32 raster stacks with rectangular vector masks determine bottom-layer opacity from representative mask windows.

The 37.8 MP opaque-base test with 2 px Feather went from 52.80 s to 0.02 s on Apple Silicon and from 69.40 s to 0.02 s under Rosetta. These are single runs on the same host.

The 300,000 × 300,000 opaque-base test at 1,000 px completed in 1.27 s on Apple Silicon and 1.79 s under Rosetta. The narrow and wide opaque controls and the distant inverted-hole control each matched 9,248 sampled Float32 words on each architecture against the corresponding build 599 37.8 MP controls.

The small inverted-hole control rendered 26 patches in build 600 and two in build 599. Its single-run Apple Silicon time increased from 0.015 s to 0.018 s. Under Rosetta it increased from 0.009 s to 0.027 s.

A 36-mask corpus matched all 859,143 coverage words against build 599 on each architecture. Every opacity result matched an exhaustive scan of its corpus case.

All 916 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both extracted universal slices passed signature and offscreen launch checks and declare macOS 14 as the minimum.

Photoshop 27.2.0 answered a version request. Its six-file Feather capture timed out before saving any controls. Fresh Photoshop samples, broader vector geometry, physical Intel and macOS 14 runtime checks, and full Photoshop byte parity remain open.

[Development record](DEVLOG.md#dev-step-600) · [Validation data](RECTANGULAR_OPACITY_600.json).
