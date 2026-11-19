# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **607** · The 10 most recent entries, newest first.

## 2026-11-19 — Step 607 — Choose sparse Photoshop layer samples across the canvas

The editable 300,000 × 300,000 RLE PSB with paint across its first row reopened in 1.72 s on Apple Silicon and 2.70 s under Rosetta. All raster bits matched. Its 4,690 retained tiles occupied about 293 MiB.

The raw and mixed-compression controls each went from 8,911 mapped tiles to 21. Row inspection preserved the live cursor and continued to reject malformed input in both PSD and PSB. All 940 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-607) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_607.md).

## 2026-11-19 — Step 606 — Reopen sparse editable PSB raster layers

Photato reopened the 8.45 GB, 300,000 × 300,000 RGB8 PSB in 1.65 s on Apple Silicon and 2.61 s under Rosetta. Every raster bit matched and six tiles used 384 KiB of mapped sample storage. The independent decoder checked 900,000 layer and 900,000 merged row lengths per architecture, plus 72 sampled channel values.

The 300,000 × 131 RGB8 file went from 14,064 mapped tiles to four. RGB16 and RGB32 PSBs and RGB8 and RGB16 PSDs reopened with every raster bit preserved in the tested deep and legacy fixtures. All 938 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-606) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_606.md).

## 2026-11-19 — Step 605 — Stream repeated rows in sparse PSB files

Photato saved the 11.26 GB editable solid-fill PSB at 300,000 × 300,000 pixels in 3.22 s and reopened it in 2.12 s. An independent reader checked all 1,200,000 merged row lengths and 140 sampled channel values. These were single runs on the same Mac.

The 300,000 × 131 RLE file was byte-identical to build 604. Save time went from 10.97 s to 0.30 s on Apple Silicon and from 17.54 s to 0.34 s under Rosetta. All 932 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-605) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_605.md).

## 2026-11-19 — Step 604 — Reuse wide vector Feather profiles at canvas edges

At 110.25 px Feather, the rounded 300,000 × 300,000 control went from 5,632 rendered patches to 119. Apple Silicon went from 110.45 s to 13.47 s. Under Rosetta it went from 171.10 s to 25.76 s. All 226,872 sampled RGBA words matched the build 603 whole render on each architecture. These are single runs on the same Mac.

All 307,518,180 RGBA words in four complete renders matched build 603 on each architecture. The controls include RGB8, RGB16, RGB32, an inverted group mask, and independent raster and pixel-mask edits. All 924 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-604) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_604.md).

## 2026-11-19 — Step 603 — Reuse exact composited tiles under solid vector Feather

The 300,000 × 75 control went from 39 rendered patches to 15. The RGB16 wide-Feather control went from 156 to 111.

The full 300,000 × 300,000 rounded-mask control completed in 6.47 s on Apple Silicon and 13.10 s under Rosetta, with 28 rendered patches. The maximum-size ellipse completed in 64.16 s on Apple Silicon and 113.97 s under Rosetta, with 9,804 rendered patches. The rounded mask at 110.25 px Feather completed in 110.45 s on Apple Silicon and 171.10 s under Rosetta, with 5,632 rendered patches. Across the three composites, all 745,024 RGBA words in 26 sampled regions matched build 602 viewports on each architecture. These are single runs on the same Mac.

All 922 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-603) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_603.md).

## 2026-11-19 — Step 602 — Skip solid pieces of dense feathered vector masks

At 1,000 px Feather, the interior viewport of the maximum-size document needed no scratch transfer, down from 51,595,425 source pixels. The whole 49,155 × 73 wide-Feather control transferred 18,434,046 source pixels, down from 36,890,622.

Whole-mask preparation for the 300,000 × 300,000 control at 110.25 px Feather took 10.39 s on Apple Silicon and 14.14 s under Rosetta. The four checked regions matched all 42,286 coverage words against build 601 viewport output on each architecture. These measurements are single runs on the same Mac.

Ten mask controls matched build 601 across all 10,873,881 Float32 coverage words per architecture. Two additional whole-canvas RGB32 layer stacks matched all 28,706,520 RGBA words per architecture. The controls cover both mask polarities, short and wide Feather through 1,000 px, Boolean holes, partial cells, and near-edge viewports on a 300,000 × 300,000 document. All 920 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-602) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_602.md).

## 2026-11-19 — Step 601 — Render sparse curved Feather from stored coverage

The sparse inverted rectangle control rendered in two patches, down from 36. The distant curved mask on a 300,000 × 300,000 canvas used 46, down from 92. Both controls matched the complete build 600 render.

All 918 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-601) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_601.md).

## 2026-11-19 — Step 600 — Prove RGB32 raster-base opacity with rectangular Feather

The 37.8 MP opaque-base test with 2 px Feather went from 52.80 s to 0.02 s on Apple Silicon and from 69.40 s to 0.02 s under Rosetta. These are single runs on the same host.

The 300,000 × 300,000 opaque-base test at 1,000 px completed in 1.27 s on Apple Silicon and 1.79 s under Rosetta. The narrow and wide opaque controls and the distant inverted-hole control each matched 9,248 sampled Float32 words on each architecture against the corresponding build 599 37.8 MP controls.

All 916 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-600) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_600.md).

## 2026-11-19 — Step 599 — Reuse wide vector-mask Feather windows

The 300,000 × 300,000 stress case with an inverted 1,000 px Feather mask completed in 35.71 s on Apple Silicon and 49.08 s under Rosetta. Build 598 exceeded the 200-second cutoff on Apple Silicon. The new whole-canvas output matched all 11,560 sampled Float32 words of the previous viewport output on each architecture.

All 914 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-599) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_599.md).

## 2026-11-19 — Step 598 — Render whole-canvas rectangular vector masks

A 300,000 × 300,000 document with a rectangular vector mask and a sparse raster edit rendered in 197 tiles in the regression test. The tile index reuses the rendered samples across the canvas. On a 37.8 MP RGB32 control, median whole-canvas render time went from 3.912 s to 0.103 s on Apple Silicon and from 8.245 s to 0.194 s under Rosetta. Each median uses three alternating runs on the same host.

All 912 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-598) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_598.md).
