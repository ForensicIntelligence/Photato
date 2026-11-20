# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **646** · The 10 most recent entries, newest first.

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

## 2026-11-19 — Step 639 — Keep vector outlines when printing

Include Vector Data preserves eligible outline shapes and text in native print and PDF output. An independent PDF check verified the vector paths and raster backdrop.

[Development record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-639) · [Details](PhotoCraftSwift/docs/VECTOR_PRINT_639.md).

## 2026-11-19 — Step 638 — Save document print settings with the artwork

Native documents retain committed print settings and hard-proof conditions. Editable PSD and PSB update supported Photoshop Print Information and Print Style fields.

All 1,171 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-638) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_638.md).

## 2026-11-19 — Step 637 — Remember print defaults and restore supported Photoshop settings

Photato remembers accepted native print defaults and restores supported Print Information and Print Style fields when opening Photoshop files.

All 1,171 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted macOS 14+ universal archive passed signature and offscreen launch checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-637) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_637.md).
