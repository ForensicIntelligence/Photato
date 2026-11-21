# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **698** · The 10 most recent entries, newest first.

## 2026-11-21 — Step 698 — Read raster alpha directly for regional Drop Shadows

Regional Drop Shadow preparation reads coverage directly from eligible raster tiles and applies the same mask sampler as the layer compositor. The spread filter skips covered samples whose distance cannot be improved by a neighbor.

The coverage copy matched the isolated compositor in RGB8, RGB16 and RGB32, including translated layers and feathered pixel masks. Dense noisy Fit fixtures with and without transparent holes matched each architecture's build 697 Float32 composite and soft-proof samples byte for byte.

475 of 476 selected tests passed in arm64 Debug, optimized Apple Silicon and Intel under Rosetta. The original PhotoCraft effect fixture failed with the same assertions in build 697. Both signed preview slices opened offscreen. Noisy previews still require per-pixel evaluation. Whole-document Fit on a maximum-size dense file still needs further work. The local Photoshop document query timed out, so Adobe shadow pixels and Fit sampling remain unverified.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-698) · [Details](PhotoCraftSwift/docs/DENSE_SHADOW_COVERAGE_698.md).

## 2026-11-21 — Step 697 — Reduce Fit and proof previews for large uniform Drop Shadows

Large RGB previews reuse uniform Drop Shadow spans while rendering the edges and output affected by sparse raster or mask changes. Eligible reduced HTTP viewports use the same path.

RGB8, RGB16 and RGB32 reductions with raster and mask edits matched the streamed renderer. The native Fit view and explicit HTTP composite, green-channel and soft-proof PNGs matched on a 300,000 × 300,000 document. The 70,000 × 520 benchmark reproduced each architecture's build 696 Float32 composite and soft-proof samples byte for byte.

474 of 475 selected tests passed in arm64 Debug, optimized Apple Silicon and Intel under Rosetta. The same original PhotoCraft effect fixture failed with identical assertions in build 696. Both signed preview slices opened offscreen. A coordinate-dependent shadow, such as one with noise, still needs the ordinary renderer. Broad edited areas and unsupported stacks also retain their prior rendering path. The local Photoshop document query timed out, so Adobe Fit sampling and Adobe shadow pixels remain unverified.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-697) · [Details](PhotoCraftSwift/docs/DENSE_SHADOW_FIT_697.md).

## 2026-11-21 — Step 696 — Render Drop Shadows in bounded canvas regions

Basic and advanced Drop Shadows now render on large RGB canvases. A viewport prepares the shifted source and the required filter margin.

Twenty-four RGB8, RGB16 and RGB32 viewport comparisons matched the whole-canvas renderer at tile and document edges. Another 384 varied viewport comparisons matched on each optimized architecture. A sparse 300,000 × 300,000 canvas found a 30,000-pixel displaced shadow and retained under 4 MiB of output tiles in the test. The native menu, advanced controls, preview, Undo, local HTTP edit and PNG were verified on that canvas size. A 4,096 × 4,096 editable PSB reopened with the same effect settings and regional pixels. All 138 prior effect fixtures produced identical direct and imported-project output on both architectures.

471 of 472 selected tests passed in arm64 Debug, optimized Apple Silicon and Intel under Rosetta. The original PhotoCraft effect fixture reproduced its existing assertions. Both signed macOS 14+ preview slices opened offscreen. The native Layer Style sheet was inspected offscreen in Light and Dark on the maximum-size document. The installed Photoshop instance timed out on a document query. Direct Adobe pixel comparison remains open. Very wide filters retain a scratch budget. A shadow already filling an entire canvas can require additional preview work. Other effects still use their existing whole-canvas limits.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-696) · [Details](PhotoCraftSwift/docs/REGIONAL_DROP_SHADOW_696.md).

## 2026-11-21 — Step 695 — Keep advanced Drop Shadows editable in PSD and PSB

Drop Shadow contour corners, anti-aliasing, noise and knockout now work through the editor and the Adobe-compatible create-composite route. Supported shadows remain editable in PSD and PSB.

A native editor test covers Preview, commit and Undo/Redo. The Photato style-patch and Adobe-compatible job tests preserve the contour and its corner flags. Owned 8-, 16- and 32-bit files reopen with their controls and Photato renders unchanged. An independent descriptor reader checked noise, knockout, anti-aliasing, local light, and all five contour points in six exports. The complete files match across all three builds tested. All 138 prior effect fixtures produced identical direct and imported-project output on both architectures.

468 of 469 selected tests passed in arm64 Debug, optimized arm64 and Intel under Rosetta. The same strict original PhotoCraft effect fixture still fails with identical assertions. The two unrelated hard-coded Automation count expectations now use the shared catalog count. The checked-in Xcode project built in arm64 Debug with signing disabled. Both signed macOS 14+ preview slices opened offscreen. The changed controls were inspected offscreen in Light and Dark. The installed Photoshop instance timed out on a document query. Exact Adobe shadow opacity, curve interpolation, anti-aliasing and randomized noise output still need Adobe-authored reference measurements. Large-canvas advanced style processing and advanced interchange for other effects remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-695) · [Details](PhotoCraftSwift/docs/ADVANCED_DROP_SHADOW_695.md).

## 2026-11-21 — Step 694 — Write layer styles by tile and reuse opacity checks

Advanced layer effects write their final pixels by tile. Ordinary raster writes also reuse an opacity result owned by a single surface.

Both tested wide oblique Pattern Overlay fits and the separate native Fit and soft-proof PNGs match build 693 byte for byte. The RGB8, RGB16 and RGB32 layer-style regression probe matched the previous build for all 138 cases in both direct rendering and imported-project rendering. The mapped-raster tests check that an edited copy and its original can certify opacity independently, and that tile writes reproduce scalar storage in each tested sample encoding and depth.

462 of 465 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The three inherited failures reproduced the same assertions: two outdated Automation count expectations and one strict original PhotoCraft effect fixture. All 27 additional Brush Dynamics and canvas diagnostics tests passed in Debug. The Xcode Debug build and both ad hoc signed macOS 14+ preview slices opened workspaces offscreen. The installed Photoshop instance timed out on a document query. The saved Photoshop Pattern Overlay reference still passes. Live Photoshop Fit sampling and physical editing cadence remain open.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-694) · [Details](PhotoCraftSwift/docs/STYLE_PIXEL_WRITES_694.md).

## 2026-11-21 — Step 693 — Reuse prepared pattern samples across render patches

Pattern Fill layers and Pattern Overlays share prepared source texels across patches of the same composition.

The 5 × 5 and 512 × 512 oblique sources matched build 692 byte for byte in both optimized architectures. Native Fit and soft proof for the separate 70,000 × 520 reference document produced the same PNGs as build 692. Tests covered negative wrap, transparent texels, linked origins, RGB8 reduced grids, source replacement and the cache budget.

460 of 463 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The same three failures reproduced build 692's assertions. Four additional storage tests passed in Debug. Both signed macOS 14+ preview slices launched offscreen. Xcode built the corrected project directly in arm64 Debug with signing disabled, then the built app opened a workspace offscreen. Wide nonperiodic fit still evaluates each source pixel. Interactive timing on fully covered maximum-size documents and Photoshop zoom comparison remain open. The local Photoshop document query timed out.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-693) · [Details](PhotoCraftSwift/docs/PATTERN_SAMPLING_693.md).

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
