# Photato Developer Diary

**[Full diary archive on GitHub](diary/README.md)** · [Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)

Source build **579** · The 10 most recent entries, newest first.

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

## 2026-11-18 — Step 574 — Add Stamp Layers and Stamp Visible

Stamp Layers combines selected artwork on a new layer. Stamp Visible does the same for visible artwork. Both preserve the original layers and can be undone in one step. Photato exposes the shortcuts in the Layer menu and supports the same operation in recorded Actions and through the API.

The saved Photoshop references match at 8, 16 and 32 bits per channel. The test documents include locked layers, clipping, hidden layers and selections across different groups. All 745 selected tests passed in each of the three configurations. Both slices of the universal validation archive passed their offscreen workspace checks.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-574) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_574.md).

## 2026-11-18 — Step 573 — Match HDR Normal rounding at the Float32 underflow boundary

On Intel, very small color contributions can disappear during 32-bit Normal compositing. Photato now matches the measured rounding, including products just below the smallest normal Float32 value. The Apple Silicon build keeps its fused calculation.

The new tests compare 57,504 straight color and alpha words with separately saved Photoshop results on each architecture. An ordinary opaque source that covers the canvas retains its original colors over uniform backdrop alpha. Grouped clipping can preserve those colors even when the base alpha varies. All 708 selected tests passed in all three configurations. The local universal archive passed both offscreen workspace checks. The translucent test also exposed a difference in Merge Visible that remains open.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-573) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_573.md).

## 2026-11-18 — Step 572 — Match Intel HDR Normal layer and group compositing

Photoshop's Intel build rounds the multiply and add separately when compositing 32-bit Normal layers. On Apple Silicon it uses a fused operation. Photato now follows those results for color, alpha and the opacity of supported groups. The tests use separately captured Photoshop results for each architecture.

The tested results match 264,192 Photoshop sample words on each architecture. That includes the masked Display P3 conversion that differed on Intel in build 571. All 705 selected tests passed in each configuration. Independent HDR clipping still differs.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-572) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_572.md).

## 2026-11-18 — Step 571 — Fix HDR PSD and PSB compression for Photoshop

Photoshop was reading plain ZIP as predicted ZIP on 32-bit layers. This could corrupt HDR colors when opening a PSD or PSB exported by Photato. New exports use the prediction expected for those layers. ZIP requests for the merged preview write raw data because Photoshop refused ZIP in that section. Photato still reads its older files.

Photoshop opened the tested files on Apple Silicon and Intel under Rosetta. The saved 32-bit grayscale samples match across both formats and save encodings. All 694 selected tests passed in each of three build configurations. The local universal archive passed both offscreen workspace checks. A separate mismatch remains in the Intel masked merge.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-571) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_571.md).

## 2026-11-18 — Step 570 — Preserve the working profile when merging before conversion

Merging eligible RGB layers before an Image Mode change now uses their working-profile samples. If the composite is already a single full-canvas layer, the conversion uses its original color and alpha planes. The existing Normal merge routine handles integer rounding for supported RGB stacks before promotion to 32 Bits/Channel.

All 35,840 words in the three valid Photoshop references match on each optimized architecture. All 678 selected tests passed in each build configuration. The two external HDR merge cases still need readable references.

[Detailed record](PhotoCraftSwift/docs/DEVLOG.md#dev-step-570) · [Validation](PhotoCraftSwift/docs/SOURCE_PUBLICATION_570.md).
