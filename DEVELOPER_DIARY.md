# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **600** · The 10 most recent entries, newest first.

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

## 2026-11-19 — Step 593 — Bound vector mask Feather on large canvases

Vector masks accept Feather through 1,000 px and keep their paths editable in native documents, PSD and PSB. The maximum sparse canvas test used four patches, and the native and HTTP settings share the same 1,000 px range.

All 904 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-593) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_593.md).

## 2026-11-19 — Step 592 — Bound Smart Filter mask Feather on large documents

Smart Filter masks accept Feather through 1,000 px and render projected mask regions on sparse large documents. The maximum sparse canvas test updates two distant mask regions. The Properties controls and Photato API use the same limit and retain an editable mask on save.

All 887 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-592) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_592.md).

## 2026-11-19 — Step 591 — Match measured fractional RGB32 Feather schedules

Aligned 32-bit raster masks now use Photoshop’s measured filter schedules at 14 fractional Feather settings. The comparisons cover texture, lines and edges. Apple Silicon matched every sample. The Intel texture comparison found five differences, each one Float32 step.

All 861 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-591) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_591.md).
