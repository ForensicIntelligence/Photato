# Source checkpoint 698

Native Swift 0.3.0, build 698, 2026-11-21.

Regional Drop Shadow preparation reads coverage directly from eligible raster tiles and applies the same mask sampler as the layer compositor. The spread filter skips covered samples whose distance cannot be improved by a neighbor.

The coverage copy matched the isolated compositor in RGB8, RGB16 and RGB32, including translated layers and feathered pixel masks. Dense noisy Fit fixtures with and without transparent holes matched each architecture's build 697 Float32 composite and soft-proof samples byte for byte.

475 of 476 selected tests passed in arm64 Debug, optimized Apple Silicon and Intel under Rosetta. The original PhotoCraft effect fixture failed with the same assertions in build 697. Both signed preview slices opened offscreen.

Noisy previews still require per-pixel evaluation. Whole-document Fit on a maximum-size dense file still needs further work. The local Photoshop document query timed out, so Adobe shadow pixels and Fit sampling remain unverified.

[Development record](DENSE_SHADOW_COVERAGE_698.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_698.json)
