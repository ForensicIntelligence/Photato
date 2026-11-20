# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **649** · The 10 most recent entries, newest first.

## 2026-11-19 — Step 649 — Place and reopen larger Photoshop originals

PSD, PSB and chunked native Smart Object sources have a local 256 MiB budget. The two previously rejected PSBs retained exact bytes and editable contents, and a 262.5 MB reference passed native and PSB round trips.

All 1,372 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview passed an offscreen launch. The Debug save-sheet check passed on an isolated rerun after the sheet missed the suite's deadline.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-649) · [Details](PhotoCraftSwift/docs/LARGE_EMBEDDED_ORIGINALS_649.md).

## 2026-11-19 — Step 648 — Keep large embedded sources once

A three-source native save dropped from 201.8 MB to 100.9 MB. The parent PSB and the three original sources kept identical bytes.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-648) · [Details](PhotoCraftSwift/docs/EMBEDDED_SOURCE_RECORDS_648.md).

## 2026-11-19 — Step 647 — Keep large generated Smart Object sources editable

Two large deep-colour Smart Objects keep editable child data in PSD and PSB. Independent checks matched all 134,316,048 child samples.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-647) · [Details](PhotoCraftSwift/docs/EMBEDDED_SMART_SOURCE_647.md).

## 2026-11-19 — Step 646 — Speed up large editable Smart Filter files

The 9-megapixel editable Smart Filter test dropped from 164.4 to 7.2 seconds on optimized Apple Silicon. Three PSD and PSB exports matched the previous Photato codec byte for byte.

All 1,357 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview passed offscreen launch checks.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-646) · [Details](PhotoCraftSwift/docs/PSD_SMART_FILTER_PAGING_646.md).

## 2026-11-19 — Step 645 — Keep Gradient Overlay editable

Standard Gradient Overlay keeps its stops and placement through PSD and PSB. Six exports of three Photoshop 27.4 RGB8 files matched all 737,280 merged RGBA samples.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-645) · [Details](PhotoCraftSwift/docs/PSD_GRADIENT_OVERLAY_645.md).

## 2026-11-19 — Step 644 — Match linked raster previews to saved mask samples

Supported linked RGB8 and RGB16 previews apply the separately quantized Photoshop layer and mask samples. Six file comparisons confirmed the tested output.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-644) · [Details](PhotoCraftSwift/docs/LINKED_PREVIEW_644.md).

## 2026-11-19 — Step 643 — Open nested Photoshop Smart Objects

An iterative decoder opens nested editable Smart Objects without exhausting the worker stack. The eight-level round trip and the previously failing Execute Actions workflow passed.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-643) · [Details](PhotoCraftSwift/docs/PSD_NESTED_SOURCES_643.md).

## 2026-11-19 — Step 642 — Read older solid shapes and their pixel masks

Older live solid-fill shapes open as editable layers and keep the separate pixel mask. Both unchanged exports matched the reference layer, mask and preview samples.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-642) · [Details](PhotoCraftSwift/docs/PSD_LEGACY_SHAPES_642.md).

## 2026-11-19 — Step 641 — Keep rounded rectangles and dashed ellipses editable

PSD and PSB retain supported solid fills, rounded corners and dotted or dashed ellipse strokes. Six independently checked exports retained the tested layer samples and shape records.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-641) · [Details](PhotoCraftSwift/docs/PSD_ROUNDED_ELLIPSE_641.md).

## 2026-11-19 — Step 640 — Keep Photoshop rectangles editable

Supported axis-aligned RGB rectangles open as editable layers. Photoshop-format tests verified the rendered samples and the retained rectangle descriptors.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-640) · [Details](PhotoCraftSwift/docs/PSD_LIVE_RECTANGLES_640.md).
