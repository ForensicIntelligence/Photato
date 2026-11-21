# Source checkpoint 697

Native Swift 0.3.0, build 697, 2026-11-21.

Large RGB previews reuse uniform Drop Shadow spans while rendering the edges and output affected by sparse raster or mask changes. Eligible reduced HTTP viewports use the same path.

RGB8, RGB16 and RGB32 reductions with raster and mask edits matched the streamed renderer. The native Fit view and explicit HTTP composite, green-channel and soft-proof PNGs matched on a 300,000 × 300,000 document. The 70,000 × 520 benchmark reproduced each architecture's build 696 Float32 composite and soft-proof samples byte for byte.

474 of 475 selected tests passed in arm64 Debug, optimized Apple Silicon and Intel under Rosetta. The same original PhotoCraft effect fixture failed with identical assertions in build 696. Both signed preview slices opened offscreen.

A coordinate-dependent shadow, such as one with noise, still needs the ordinary renderer. Broad edited areas and unsupported stacks also retain their prior rendering path. The local Photoshop document query timed out, so Adobe Fit sampling and Adobe shadow pixels remain unverified.

[Development record](DENSE_SHADOW_FIT_697.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_697.json)
