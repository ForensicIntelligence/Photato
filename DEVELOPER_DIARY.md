# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **603** · The 10 most recent entries, newest first.

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

## 2026-11-19 — Step 597 — Reuse window sums during wide mask Feather

Wide Feather reuses the second filter pass’s window sums when they fit a bounded cache. The 1,000 px vector viewport went from 1.001 s to 0.933 s on Apple Silicon. The RGB32 pixel-mask control went from 0.180 s to 0.135 s and the oversize Smart Filter mask from 0.867 s to 0.821 s. These are medians of three alternating runs on the same host. All 1,155 sampled Float32 coverage or output words matched build 596 bit for bit on each architecture across eight vector, raster and Smart Filter cases.

All 909 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-597) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_597.md).

## 2026-11-19 — Step 596 — Reuse source bands during wide mask Feather

Wide Feather reuses source row bands for vector, pixel and Smart Filter masks. The 1,000 px vector viewport went from 1.343 s to 0.995 s on Apple Silicon. The oversize Smart Filter mask control went from 1.483 s to 0.862 s. These are medians of three alternating runs on the same host. All 1,155 sampled Float32 coverage or output words matched build 595 bit for bit on each architecture across eight vector, raster and Smart Filter cases.

All 908 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-596) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_596.md).

## 2026-11-19 — Step 595 — Prepare vector-mask Feather around the viewport

Large-canvas vector-mask Feather limits broad coverage preparation to the viewport and its filter margin. On Apple Silicon, the 15 × 7 viewport through a 24,576 px mask at 1,000 px Feather took 8.506 s in build 594 and 1.367 s in build 595. The 250 px curved control took 6.063 s and 0.206 s.

All 907 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-595) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_595.md).

## 2026-11-19 — Step 594 — Match measured short vector-mask Feather responses

The 1.5 px and 2 px vector-mask Feather settings now reproduce the measured Photoshop step and corner responses. Dense rendering, paged whole-canvas rendering and tiled viewports produced identical alpha words at the tested coordinates.

All 905 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-594) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_594.md).
