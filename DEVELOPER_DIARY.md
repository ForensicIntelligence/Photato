# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **584** · The 10 most recent entries, newest first.

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

## 2026-11-18 — Step 580 — Match Screen clipping and unchanged stamp history

Screen clips now participate in supported RGB8 and RGB16 merges and stamps. In-place stamps create an Undo step even when the stored pixels stay identical.

The saved-layer comparisons cover 36 Photoshop results. The 12 larger results account for 93,264 exact stored samples. The native editor and both local API families use the same implementation. All 765 selected checks passed in each configuration.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-580) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_580.md).

## 2026-11-18 — Step 579 — Add in-place Stamp Down and Stamp Group

Option-Command-E now stamps into an existing raster when one eligible layer is selected. Stamp Down updates the layer beneath it. Stamp Group updates the base of a supported clipping stack. Both commands preserve the selected layer and the rest of the stack.

The updated raster matched saved 8-, 16- and 32-bit Photoshop references. The native menu, local API, Actions and Undo share the two operations. All 761 selected tests passed in each of the three configurations.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-579) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_579.md).

## 2026-11-18 — Step 578 — Add contextual Merge Clipping Mask

Selecting the base of a supported raster clipping stack now makes Command-E run Merge Clipping Mask. The command combines visible clips into the base and removes the consumed clips. Hidden clips contribute no color. The base keeps its opacity, blend mode and stored geometry, including transparent or off-canvas samples.

The save-and-reopen tests compare 8-, 16- and 32-bit Photoshop reference layers. Undo, Actions and both local Adobe-compatible job routes are covered. All 757 selected checks passed on each of the three build configurations.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-578) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_578.md).

## 2026-11-18 — Step 577 — Preserve stored RGB32 pixel masks when merging and stamping

Normal 32-bit layer output now uses stored pixel masks. The comparison covers saved binary coverage and feathered selections, including transparency and the Intel rounding at tiny alpha values. A small translated mask in a 300,000 × 300,000 document used two render patches.

All 752 selected tests passed in Debug and in both optimized configurations. Both slices of the extracted local validation archive passed their offscreen checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-577) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_577.md).

## 2026-11-18 — Step 576 — Match stored RGB32 Normal merge and stamp samples

Merging and stamping 32-bit Normal layers now matches the saved Photoshop samples in the tested raster stacks. These tests cover very low alpha, transparent pixels, partial layer opacity and an opaque Background. A fresh Intel capture also confirmed that its saved alpha differs from Apple Silicon on one older fixture.

The new tests compare the stored layer before and after reopening a PSD. All 750 selected tests passed in each of the three build configurations. Both slices in the local universal archive passed their offscreen checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-576) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_576.md).

## 2026-11-18 — Step 575 — Render sparse stamps at maximum canvas size

Stamp Layers and Stamp Visible now skip large empty areas of a sparse document. A 300,000-pixel-square test document with two separated layers used two render patches. The tests covered raster stacks, simple groups, a translucent canvas background and both stamp operations at 8, 16 and 32 bits per channel.

Both ActionJSON job routes matched saved Photoshop layer samples for tagged and untagged files. All 749 selected tests passed in all three build configurations. Both slices of the local universal archive passed their offscreen checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-575) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_575.md).
