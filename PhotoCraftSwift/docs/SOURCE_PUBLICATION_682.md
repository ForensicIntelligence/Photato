# Source checkpoint 682

Native Swift 0.3.0, build 682, 20 November 2026.

Gradient, pattern, and stroke paint on a large shape cutout now renders over the visible area. Panning retains the full shape’s paint coordinates and antialiasing.

All 297 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

The owned 100 × 60 viewport, 120 × 84 thumbnail, and editable native file matched byte for byte across all three builds. Thirteen earlier shape outputs and three editable PSD/PSB cutout outputs remained byte-identical to their reference builds. The maximum-canvas tests cover an editable gradient and stroke and a sparse solid fill with an editable gradient stroke. Affine patches and full rasterization matched at 8, 16, and 32 bits per channel in the owned cases. A patterned shape with a separate pixel mask also matched between paged composition and a viewport. The 70-megapixel rasterization probe used mapped storage and reproduced its reference viewport bytes.

The median CPU composite for the 1,920 × 1,080 viewport was 226.79 ms in the optimized Apple Silicon probe with one visible painted shape.

Gradient and pattern shape paint remain editable in native files. Editable Photoshop file transport for this paint and a live Photoshop comparison are still open. Whole-document materialization uses the available scratch storage. Full editing frame rate remains a separate measurement.

[Development record](BOUNDED_SHAPE_PAINT_682.md) · [Developer Diary](DEVELOPMENT_DIARY.md) · [Validation data](SOURCE_PUBLICATION_682.json)
