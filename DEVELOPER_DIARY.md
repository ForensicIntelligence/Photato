# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **692** · The 10 most recent entries, newest first.

## 2026-11-21 — Step 692 — Reduce wide oblique Pattern Overlays in bounded patches

Fit on Screen and the local PNG overview reduce supported wide oblique Pattern Overlays without retaining the full composite.

Fractional edges matched retained rendering at RGB8, RGB16 and RGB32 in the tested composite, channel and proof views. The proof test also preserved a sparse implicit backdrop across the maximum canvas. Authenticated composite, channel and proof PNGs matched their retained native controls. The separate AppKit probe fitted and proofed a fully covered 70,000 × 520 document on both architectures.

458 of 461 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The same three failures reproduced build 691's assertions. Both signed macOS 14+ preview slices launched offscreen. Large nonperiodic fits still evaluate source pixels and can take seconds or longer. End-to-end timing for a fully covered maximum-size oblique Fit remains open. The Photoshop 2026 document-count query timed out, leaving live zoom comparison open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-692) · [Details](PhotoCraftSwift/docs/PAGED_PATTERN_REDUCTION_692.md).

## 2026-11-21 — Step 691 — Fit quarter-turn Pattern Overlays on large canvases

Fit on Screen and the local PNG overview now handle eligible quarter-turn Pattern Overlays on canvases up to 300,000 × 300,000.

Actual-size crops from four parts of the canvas matched the ordinary compositor in RGB8, RGB16 and RGB32. Six angle, scale and phase combinations also matched an independent whole-period area control. The native test exercised Fit, pan, Brush, Undo and the authenticated overview. An owned 90° probe with a sparse edit produced identical fit and actual-size bytes across all three test configurations.

455 of 458 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The same three failures reproduced build 690’s assertions. Both signed macOS 14+ preview slices launched offscreen. The optimization requires a dyadic scale and Float32-safe phase on both pattern axes. Integral-phase 100% placements that fail this proof and oblique angles retain the existing path. Large nonperiodic Fit on Screen and live Photoshop zoom comparison remain open. The installed Photoshop 2026 document-count query timed out.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-691) · [Details](PhotoCraftSwift/docs/QUARTER_TURN_PATTERN_691.md).

## 2026-11-21 — Step 690 — Bound rotated Pattern Overlay viewports

Rotated and nonperiodic Pattern Overlay renders in bounded document viewports on canvases up to 300,000 × 300,000.

At actual size, overlapping panned views matched at 8-, 16-, and 32-bit depth. A 31° pattern at 56% matched the ordinary renderer at actual size, at fractional zoom and above the direct in-memory patch limit. The native canvas and all three local PNG viewport routes produced identical PNGs in the tested RGB8 composite, channel and proof views. Eighteen samples from the saved Adobe Photoshop PSD also matched.

453 of 456 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. The same three failures reproduced the build 689 assertions. Both signed macOS 14+ preview slices launched offscreen. Fit-to-window on very large nonperiodic canvases still uses full rendering. The bounded route has a source budget of 16,777,216 pixels and an output budget of 4,194,304 pixels. Photoshop’s document-count query timed out, so direct comparison of live zoom presentation remains open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-690) · [Details](PhotoCraftSwift/docs/PATTERN_VIEWPORT_690.md).

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
