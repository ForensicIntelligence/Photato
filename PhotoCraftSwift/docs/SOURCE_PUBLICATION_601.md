# Source checkpoint 601

Native Swift 0.3.0, build 601, 19 November 2026. Large feathered vector masks use stored coverage to limit render work. Sparse inverted rectangles use the existing affected-tile renderer when it has less work.

Five controls matched build 600 bit for bit on each architecture. The comparison hashes the implicit RGBA sample, the index of every tile containing a different sample, and every visible RGBA word in those tiles. The controls cover a sparse inverted rectangle, a narrow curve, a wide-Feather curve, a broad curve and a narrow curve near the far corner of a maximum-size canvas.

The sparse rectangle used two render patches, down from 36. The curve on a 300,000 × 300,000 canvas used 46, down from 92. The maximum-size case took 0.19 s on Apple Silicon, down from 1.07 s, and 0.33 s under Rosetta, down from 2.04 s. These times are from single runs on the same Mac.

All 918 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both extracted universal app slices passed signature and offscreen launch checks. The package declares macOS 14 as its minimum.

The installed Photoshop app timed out on both read-only document count requests. Fresh Photoshop outputs, maximum-size dense curved masks, physical Intel and macOS 14 runtime checks, and full Photoshop byte parity remain open.

[Development record](DEVLOG.md#dev-step-601) · [Validation data](CURVED_VECTOR_SUPPORT_601.json).
