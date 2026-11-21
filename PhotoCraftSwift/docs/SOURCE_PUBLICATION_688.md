# Source checkpoint 688

Native Swift 0.3.0, build 688, 2026-11-21.

Basic RGB Pattern Overlay can be edited and previewed on sparse canvases up to 300,000 × 300,000.

Across RGB8, RGB16 and RGB32, a 30 × 30 crop that crossed tile boundaries matched the small-canvas control byte for byte. The test covered linked and document-relative placement, partial layer coverage, a pixel mask, and a translucent backdrop. The largest PSB reopened through the native file-backed reader and preserved the style and all 3,600 crop bytes. A 6,000 × 2,000 PSB was byte-identical across the three builds. The loopback API applied and patched the overlay on a maximum-size document and transferred an editable 4,096 × 4,096 PSB.

448 of 451 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Three failures repeated with the same assertions as build 687. Both signed macOS 14+ preview slices launched offscreen.

Dense full-canvas output, mixed spatial effects and maximum-size HTTP PSB transfers remain open. Photoshop 2026 reported version 27.2.0. Its document and JavaScript commands timed out, so live pixel and reopen comparisons remain open.

[Development record](LARGE_PATTERN_OVERLAY_688.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_688.json)
