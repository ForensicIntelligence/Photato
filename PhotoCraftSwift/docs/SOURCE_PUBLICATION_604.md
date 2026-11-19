# Source checkpoint 604

Native Swift 0.3.0, build 604, 19 November 2026. Wide feathered vector masks reuse identical edge profiles in both the filter and the compositor.

All 307,518,180 RGBA words in four complete renders matched build 603 on each architecture. The controls include RGB8, RGB16, RGB32, an inverted group mask, and independent raster and pixel-mask edits.

At 110.25 px Feather, the rounded 300,000 × 300,000 control went from 5,632 rendered patches to 119. Apple Silicon went from 110.45 s to 13.47 s. Under Rosetta it went from 171.10 s to 25.76 s. All 226,872 sampled RGBA words matched the build 603 whole render on each architecture. These are single runs on the same Mac.

The full-size ellipse on Apple Silicon exceeded the 520 s diagnostic limit. The full-size ellipse on Rosetta exceeded the 520 s diagnostic limit.

All 924 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both extracted universal app slices passed signature and offscreen launch checks. The package declares macOS 14 as its minimum.

Photoshop returned an AppleEvent timeout on a read-only document count. Fresh Photoshop samples, full-size PSB export, physical Intel and macOS 14 runtime, and full Photoshop byte parity remain open.

[Development record](DEVLOG.md#dev-step-604) · [Validation data](WIDE_VECTOR_PROFILES_604.json).
