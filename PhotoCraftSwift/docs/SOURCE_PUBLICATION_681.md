# Source checkpoint 681

Native Swift 0.3.0, build 681, 20 November 2026.

Moving a cutout now moves its contour while the fill reaches the current canvas edges. Canvas Size and Crop update the exterior, and supported PSD and PSB files retain the editable shape.

All 292 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

The three owned reframe outputs matched byte for byte across all three builds. All 13 previously qualified rectangle and ellipse outputs also matched build 680. Two saved Layer Comp positions preserved every canvas byte after native, PSD, and PSB reopening. An independent PSD reader confirmed the live rectangle origin, the shifted four-knot contour, the subtract operation, and all alpha and visible RGB samples in both formats.

Rendering the solid shape source in the 4,200 × 2,800 benchmark took a median of 1.26 ms, down from 265.22 ms in build 680. The timing covers preparation of one layer’s pixels. Full editing frame rate remains a separate measurement.

The owned live Photoshop comparison timed out. Adobe’s public vector-mask and canvas documentation informed the expected behavior. Exact Photoshop live-shape output, transformed exteriors and very large styled fills remain open.

[Development record](EDITABLE_SHAPE_CANVAS_681.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_681.json)
