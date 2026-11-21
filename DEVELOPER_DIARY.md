# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **689** · The 10 most recent entries, newest first.

## 2026-11-21 — Step 689 — Preview opaque Pattern Overlay on large canvases

The native editor and local API preview supported opaque Pattern Overlay on canvases up to 300,000 × 300,000.

Fit uses the area covered by each screen pixel. At 100% the preview reads the same samples as a full render. Painted pixels, aligned pixel masks and translated raster layers remain visible. Tests also checked isolated RGB channels, soft proofing, native Brush and Undo, and a 2,048 × 2,048 PNG from the local API.

451 of 454 selected tests passed in each of Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Three inherited failures reproduced build 688’s assertions. Both signed macOS 14+ preview slices launched offscreen. The preview requires supported axis-aligned pattern periods and bounded local changes. Other angles and nonperiodic scales still use ordinary rendering. Full-resolution export has its own capacity limits. Photoshop’s document-count query timed out, so live zoom and preview equivalence remain unverified.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-689) · [Details](PhotoCraftSwift/docs/OPAQUE_PATTERN_PREVIEW_689.md).

## 2026-11-21 — Step 688 — Render Pattern Overlay on large canvases

Basic RGB Pattern Overlay can be edited and previewed on sparse canvases up to 300,000 × 300,000.

Across RGB8, RGB16 and RGB32, a 30 × 30 crop that crossed tile boundaries matched the small-canvas control byte for byte. The test covered linked and document-relative placement, partial layer coverage, a pixel mask, and a translucent backdrop. The largest PSB reopened through the native file-backed reader and preserved the style and all 3,600 crop bytes. A 6,000 × 2,000 PSB was byte-identical across the three builds. The loopback API applied and patched the overlay on a maximum-size document and transferred an editable 4,096 × 4,096 PSB.

448 of 451 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Three failures repeated with the same assertions as build 687. Both signed macOS 14+ preview slices launched offscreen. Dense full-canvas output, mixed spatial effects and maximum-size HTTP PSB transfers remain open. Photoshop 2026 reported version 27.2.0. Its document and JavaScript commands timed out, so live pixel and reopen comparisons remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-688) · [Details](PhotoCraftSwift/docs/LARGE_PATTERN_OVERLAY_688.md).

## 2026-11-20 — Step 687 — Keep Pattern Overlay editable in PSD and PSB

Photato now opens and saves supported Photoshop Pattern Overlays as editable layer effects with embedded tiles.

The Photoshop-authored document retained all 13 layers, six editable overlays, and all 196,608 merged RGB bytes in unchanged PSD and PSB exports. Changes to all six overlays reopened with their revised settings. The four exports were byte-identical across build configurations.

446 of 449 selected tests passed in each configuration, including Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Three failures repeated on build 686 with the same assertions. Both signed macOS 14+ preview slices launched offscreen. The Photoshop color comparison covers the authored linked Normal overlays at 200% and 50% opacity. The existing style renderer still limits canvas area to 8,388,608 pixels. Other blend modes, rotated and fractional placement, and live Photoshop 2026 reopening require further comparison.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-687) · [Details](PhotoCraftSwift/docs/EDITABLE_PATTERN_OVERLAY_687.md).

## 2026-11-20 — Step 686 — Match sampled Photoshop legacy pattern scales

Legacy RGB8 shape patterns now use rounded half-size tiles and quantized corner interpolation in supported cases.

At 25%, 50%, 56%, and 200% the regenerated layer colors matched all 9,309 sampled opaque interior pixels per case. Four other pattern-placement cases matched the same number of pixels each. The edited and untouched exports were byte-identical across build configurations. The native saves and both Photoshop formats reopened with editable patterns.

All 351 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both signed macOS 14+ preview slices launched offscreen. The comparisons cover the authored tiles and placements. Rotated and transparent tiles, odd-size reductions, other depths, and full shape-edge output still require comparison. Preparing a synthetic 4,000 × 4,000 sparse tile at 25% took 0.75 seconds on this test Mac. Live Photoshop 2026 reopen remains unverified.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-686) · [Details](PhotoCraftSwift/docs/LEGACY_PATTERN_SCALING_686.md).

## 2026-11-20 — Step 685 — Improve RGB8 shape opacity and legacy pattern placement

Plain Normal RGB8 shape layers round effective and accumulated alpha at each layer. Supported legacy pattern shapes retain editable phase and the original reference point in PSD and PSB.

All 310 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Scaled pattern repaint at 200%, 56%, and 25% still differs. Independent sampling matched the 200% fixture with a half-pixel coordinate shift and the 25% fixture with two rounded 2 × 2 reductions. Masked, styled, transformed and other depth or blend cases have separate acceptance requirements. Reopening in a live Photoshop 2026 session remains unverified.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-685) · [Details](PhotoCraftSwift/docs/SHAPE_EDGE_COMPOSITING_685.md).

## 2026-11-20 — Step 684 — Keep patterns and straight lines editable in PSD and PSB

Supported RGB8 and RGB16 PSD and PSB shape layers keep their embedded pattern fills and strokes editable. Arrowless straight lines retain their endpoints and weight.

All 302 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. The regenerated merged preview differs in 331 color-channel bytes across 224 antialiased pixels, with a maximum difference of 1 in RGB and exact alpha. The 56% polygon pattern sample supports a document-origin phase. Its scaled sampling still differs. The 60° gradient diagnostic did not establish a universal half-pixel placement correction. Arrowheads and live Photoshop 2026 reopen and repaint checks remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-684) · [Details](PhotoCraftSwift/docs/EDITABLE_SHAPE_PATTERNS_684.md).

## 2026-11-20 — Step 683 — Keep shape gradients editable in PSD and PSB

Supported RGB8 and RGB16 shape layers retain their editable gradient fills and strokes in PSD and PSB. An unchanged import keeps its source descriptors and pixel cache.

All 300 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. The original file containing patterned shape paint and the original file containing unsupported pattern layer effects still reject. The derivative fixtures isolate shape metadata and leave pattern paint, line controls, seeded dither and whole-file compatibility open. An equivalent-angle native repaint differed in alpha by up to three 8-bit levels throughout a 32 × 32 interior sample. Its RGB values matched. A separate diagnostic shifted the gradient center by half a pixel and matched all 1,024 alpha samples in that window. Reopening the new files in a live Photoshop 2026 session remains unverified.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-683) · [Details](PhotoCraftSwift/docs/EDITABLE_SHAPE_PAINT_683.md).

## 2026-11-20 — Step 682 — Render gradients and strokes on large editable cutouts

Gradient, pattern, and stroke paint on a large shape cutout now renders over the visible area. Panning retains the full shape’s paint coordinates and antialiasing.

All 297 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Gradient and pattern shape paint remain editable in native files. Editable Photoshop file transport for this paint and a live Photoshop comparison are still open. Whole-document materialization uses the available scratch storage. Full editing frame rate remains a separate measurement.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-682) · [Details](PhotoCraftSwift/docs/BOUNDED_SHAPE_PAINT_682.md).

## 2026-11-20 — Step 681 — Keep the shape exterior attached to the canvas

Moving a cutout now moves its contour while the fill reaches the current canvas edges. Canvas Size and Crop update the exterior, and supported PSD and PSB files retain the editable shape.

All 292 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. The owned live Photoshop comparison timed out. Adobe’s public vector-mask and canvas documentation informed the expected behavior. Exact Photoshop live-shape output, transformed exteriors and very large styled fills remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-681) · [Details](PhotoCraftSwift/docs/EDITABLE_SHAPE_CANVAS_681.md).

## 2026-11-20 — Step 680 — Subtract the first component of a shape layer

A leading Subtract cuts a hole in the shape layer’s canvas fill. The contour remains editable in Photato and in supported PSD and PSB files.

All 287 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen. Sparse full-canvas rendering has been qualified for an integer-aligned solid fill on a 300,000 × 300,000 document without a visible stroke. The exterior currently retains the canvas frame set when it was created. Canvas resizing, moved or rotated exteriors in PSD, large gradients and strokes, and a direct Photoshop comparison of live shape data remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-680) · [Details](PhotoCraftSwift/docs/SHAPE_SUBTRACTION_680.md).
