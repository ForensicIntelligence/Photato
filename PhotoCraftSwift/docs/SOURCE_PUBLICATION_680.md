# Source checkpoint 680

Native Swift 0.3.0, build 680, 20 November 2026.

A leading Subtract cuts a hole in the shape layer’s canvas fill. The contour remains editable in Photato and in supported PSD and PSB files.

All 287 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

The PSD, PSB, and RGBA cutout outputs matched byte for byte across all three builds. An independent PSD reader confirmed the live rectangle origin, all four editable knots, the subtract operation, and every alpha and visible RGB sample in the cutout caches. Recreating an existing Photoshop 2026 Subtract-then-Intersect vector mask as a native shape matched all 24,576 red and green samples. The 10 owned ellipse outputs also matched byte for byte across all three builds. They included native archives at three depths and editable RGB8 and RGB16 PSD and PSB files.

Sparse full-canvas rendering has been qualified for an integer-aligned solid fill on a 300,000 × 300,000 document without a visible stroke. The exterior currently retains the canvas frame set when it was created. Canvas resizing, moved or rotated exteriors in PSD, large gradients and strokes, and a direct Photoshop comparison of live shape data remain open.

[Development record](SHAPE_SUBTRACTION_680.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_680.json)
