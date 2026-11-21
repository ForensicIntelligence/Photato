# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **702** · The 10 most recent entries, newest first.

## 2026-11-21 — Step 702 — Keep editable Generative Fill variations

Prompted Generative Fill can now keep up to three results in one editable masked layer. Choose a variation in Properties or through the Photato API. The original generation takes one Undo step.

Synthetic RGB8, RGB16 and RGB32 tests preserved exact rendered samples, mask coverage and the selected variation after reopening Photato, PSD and PSB files in Photato. The real Core ML model generated identical first results through the editor and HTTP at the tested seed. A separate sandboxed test generated three different results and preserved all 49,283 pixels outside the selection in each. Each of those real variations also matched its original RGBA bytes after reopening in all three formats in Photato.

482 of 483 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The original PhotoCraft layer-effect fixture repeated its 118 assertions from build 701 in each configuration. Both signed preview slices opened offscreen and the checked-in Xcode project built in arm64 Debug. Generating more results into the same layer, Generate Similar, the Adobe Execute Actions descriptor, and Firefly pixel equivalence remain open. The installed Photoshop session timed out on two read-only scripting queries. Adobe's desktop documentation confirms variation selection in Properties.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-702) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_702.md).

## 2026-11-21 — Step 701 — Blend Generative Fill selection edges

Generative Fill now uses opaque pixels around the selection to reduce color seams. The correction tapers into the selected area. The editor and Photato API preserve the editable mask and one-step Undo.

Mean RGB8 drift across 505 boundary samples fell from 4.39 to 0.31 levels on the apple and from 3.95 to 0.24 on the mug. Each result preserved all 49,283 protected samples and all 9,898 tested interior samples. Both fills retained exact pixels and editable masks when reopened in Photato as native, PSD and PSB files. A synthetic fill exercised a 4,194,304-pixel selection on a 300,000 × 300,000 sparse canvas.

480 of 481 selected tests passed in arm64 Debug, optimized Apple Silicon and optimized Intel under Rosetta. The original PhotoCraft effect fixture reproduced build 700’s assertions. Both signed preview slices opened offscreen, and the checked-in Xcode project built in arm64 Debug. Application-managed variation sets and the Adobe Execute Actions descriptor remain open. A separate seed probe hit a Core ML GPU exception once and succeeded on retry. The installed Photoshop session timed out on a read-only scripting query, so Photoshop output equivalence has yet to be verified.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-701) · [Qualification](PhotoCraftSwift/docs/SOURCE_PUBLICATION_701.md).

## 2026-11-21 — Step 700 — Add prompted Generative Fill on Apple Silicon

Generative Fill accepts a text prompt and selection mask in Photato’s native editing sheet and HTTP API. An optional Core ML model generates the content locally. The existing blank-prompt mode uses LaMa512.

Using the same source, selection and seed, a red-apple prompt and a blue-mug prompt produced distinct subjects. The native and authenticated HTTP paths matched RGB8 output bytes for the same prompt and seed. Both prompts preserved all 49,283 protected pixels. The editable mask retained feathering and a protected hole, and one Undo restored the original document. Both edits reopened in Photato with exact RGB8 composites and mask coverage in native, PSD and PSB files.

477 of 478 selected tests passed in arm64 Debug, optimized Apple Silicon and optimized Intel under Rosetta. The original PhotoCraft effect fixture reproduced build 699’s assertions. Both signed preview slices opened offscreen. The checked-in Xcode project built in arm64 Debug, and the sheet was inspected offscreen in Light and Dark. Hard selection edges can show a tonal seam. Editable variation sets, Adobe Execute Actions descriptor compatibility and Firefly output equivalence remain open. The installed Photoshop session timed out on both scripting queries.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-700) · [Model setup](PhotoCraftSwift/docs/LOCAL_GENERATIVE_FILL.md).

## 2026-11-21 — Step 699 — Add local Generative Fill from surrounding pixels

Generative Fill now uses an optional Apple Silicon Core ML model to fill a selection from surrounding pixels. Photato places the result above the visible stack on a raster layer with an editable mask and one Undo step.

The pinned LaMa512 model ran in Debug and optimized Apple Silicon builds. The native transaction and authenticated loopback API returned identical composite samples on the same RGB8 fixture. Tests at RGB8, RGB16 and RGB32 matched protected pixels and every output-mask sample. The owned example retained the editable mask on native, PSD and PSB reopening in Photato.

476 of 477 selected tests passed in arm64 Debug, optimized Apple Silicon and Intel under Rosetta. The original PhotoCraft effect fixture failed with identical assertions in build 698. Both signed preview slices opened offscreen. The local provider fills from context. Text prompts, variant sets and Adobe Execute Actions support remain open. The installed Photoshop session timed out, so Adobe output and physical workflow comparison remain pending.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-699) · [Details](PhotoCraftSwift/docs/GENERATIVE_FILL_699.md).

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
