# Source checkpoint 696

Native Swift 0.3.0, build 696, 2026-11-21.

Basic and advanced Drop Shadows now render on large RGB canvases. A viewport prepares the shifted source and the required filter margin.

Twenty-four RGB8, RGB16 and RGB32 viewport comparisons matched the whole-canvas renderer at tile and document edges. Another 384 varied viewport comparisons matched on each optimized architecture. A sparse 300,000 × 300,000 canvas found a 30,000-pixel displaced shadow and retained under 4 MiB of output tiles in the test. The native menu, advanced controls, preview, Undo, local HTTP edit and PNG were verified on that canvas size. A 4,096 × 4,096 editable PSB reopened with the same effect settings and regional pixels. All 138 prior effect fixtures produced identical direct and imported-project output on both architectures.

471 of 472 selected tests passed in arm64 Debug, optimized Apple Silicon and Intel under Rosetta. The original PhotoCraft effect fixture reproduced its existing assertions. Both signed macOS 14+ preview slices opened offscreen. The native Layer Style sheet was inspected offscreen in Light and Dark on the maximum-size document.

The installed Photoshop instance timed out on a document query. Direct Adobe pixel comparison remains open. Very wide filters retain a scratch budget. A shadow already filling an entire canvas can require additional preview work. Other effects still use their existing whole-canvas limits.

[Development record](REGIONAL_DROP_SHADOW_696.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_696.json)
