# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **590** · The 10 most recent entries, newest first.

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

## 2026-11-19 — Step 585 — Add three arithmetic clipping blend modes

Linear Dodge (Add), Subtract and Divide now work in supported raster clipping merges and stamps at 8, 16 and 32 bits per channel. The HDR checks include masked clips, mixed opacity and translated Divide layers.

All 787 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The tests compare 96 saved Photoshop results per architecture.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-585) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_585.md).

## 2026-11-19 — Step 584 — Preserve pixel masks in clipping merges and stamps

Supported clipping merges and stamps preserve the editable base pixel mask and apply contributing masks at 8, 16 and 32 bits per channel. The tests cover disabled masks, integer offsets, Density and partial clip opacity. Stamp Group and Stamp Down retain the contributing mask on its own layer.

All 782 selected checks passed in Debug, optimized Apple Silicon and Intel under Rosetta. Feather on a contributing mask remains in development.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-584) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_584.md).

## 2026-11-18 — Step 583 — Add four clipped blend modes

Multiply, Darken, Lighten and Difference now participate in supported raster clipping merges and stamps at 8, 16 and 32 bits per channel.

The saved Photoshop comparison matched 62,736 stored sample words per architecture. All 776 selected checks passed in Debug, optimized Apple Silicon and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-583) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_583.md).

## 2026-11-18 — Step 582 — Preserve independent clipping in merges and stamps

Supported raster clipping merges and stamps preserve Blend Clipped Layers as Group, the base blend mode, and its opacity. The saved pixels for the tested Multiply cases matched with the underlying backdrop visible or hidden.

The native editor and both local API families share the updated behavior. All 773 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-582) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_582.md).

## 2026-11-18 — Step 581 — Merge and stamp adjacent clipped layers

Merge Down and Stamp Down now work between adjacent Normal raster clips in the same clipping stack. Merge Down keeps the destination clipped and removes the upper layer. Stamp Down keeps both rows and the upper selection.

The stored raster matches the tested 8-, 16- and 32-bit Photoshop outputs. The first ActionJSON expansion found a stack overflow. Reusing the raster-output helper repaired it, and all 769 selected tests passed on each configuration.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-581) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_581.md).
