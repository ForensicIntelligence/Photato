# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **595** · The 10 most recent entries, newest first.

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

## 2026-11-19 — Step 590 — Match integer raster-mask Feather stages

Aligned RGB8 and RGB16 raster-layer masks now use integer-rounded Feather stages in rendering and clipping merges. The 34 Photoshop control files cover points, textures and translated masks. An independent reader checked 51,578 native PSD colour words in each test configuration. All matched the saved Apple Silicon Photoshop references.

All 858 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta. The independent Photoshop Rosetta capture remains pending.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-590) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_590.md).

## 2026-11-19 — Step 589 — Apply Feather in raster clipping merges and stamps

Merge Clipping Mask, Stamp Group, and eligible Merge Down and Stamp Down commands now use Feather on contributing raster clips. Saved RGB32 layer output matches five Photoshop cases at 250 or 1,000 px on both architectures. The tests also exercise sparse 300,000 × 300,000 documents and verify Undo through the desktop model and HTTP.

All 856 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta. The lower-radius Intel comparisons still have differences of up to two Float32 steps.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-589) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_589.md).

## 2026-11-19 — Step 588 — Support layer-mask Feather through 1,000 px

Layer-mask Feather now accepts 0–1,000 px in the native controls, Photato API and editable files. The renderer streams the wide filter. The saved 250 and 1,000 px RGB32 controls match exactly on both tested architectures, and the editable 1,000 px setting survives native, PSD and PSB round trips.

All 850 selected checks passed across the suite and focused recheck in Debug, optimized Apple Silicon and Intel under Rosetta. Fractional settings and other mask geometries still need exact Photoshop comparisons.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-588) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_588.md).

## 2026-11-19 — Step 587 — Match staged RGB32 pixel-mask Feather

Aligned RGB32 layer masks use a staged square filter at whole-pixel Feather radii from 3 to 100 px. It follows the canvas and stored mask edges, including masks that extend outside the canvas. In the app tests, 34,975 coverage samples matched the 21 saved Apple Silicon references exactly. All 844 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta.

Photoshop's 250 and 1,000 px textured controls also match the model. The current app range is 100 px. Fractional radii, a few Intel rounding cases, and the wider control are still in development.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-587) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_587.md).

## 2026-11-19 — Step 586 — Bound pixel-mask Feather rendering

Pixel-mask Feather now renders requested regions on 300,000 × 300,000 documents without preparing a full padded mask. Existing Feather output is preserved across the tested depths and transforms. All 842 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta.

Separate Photoshop tests reproduced the saved 100, 250 and 1,000 px line samples. The two-dimensional Intel results still need investigation before widening the control.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-586) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_586.md).
