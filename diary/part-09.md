[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Next page](part-08.md)

## 2026-11-23 — Step 721 — Preserve editable type and RGB32 composites in layered Photoshop files

Layered PSD and PSB exports place the editable text record and its padding before the following protection record. Photato can still open older files written with the uncounted pad. Whole-pixel translations of editable text now render the same way before and after reopening an RGB32 file.

The mixed document keeps editable type and its protection settings, group and pixel masks, an Exposure adjustment, and a projected embedded Smart Object with an editable Gaussian Blur and filter mask. Initial and edited reopens match every rendered RGBA byte at 8, 16 and 32 bits per channel in PSD and PSB. An independent reader recovered the tagged structure in all twelve files per configuration. An independent comparison matched 294,912 stored merged channel words per configuration, including the transparency plane. Authenticated Photato downloads matched the native files byte for byte.

The test uses exact file-representable group opacity. Photoshop files store the group opacity in one byte, so a literal 84% differs from the saved 214/255. These tests use owned input and compare round-trip output with Photato’s own pre-save render. Direct Photoshop reopening, Adobe pixel equivalence, linked asset rebind and broader Smart Filter ordering remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-721) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_721.md).

## 2026-11-23 — Step 720 — Recover partial transparency in product cutouts

Select and Mask can recover partial coverage from a rough selection. Estimate a smooth background or choose an aligned photo of an empty textured backdrop. Erase Refinement restores the input coverage where you brush. Decontaminate Colors removes the backing color and the result can keep an editable mask or export as transparent PNG. The Photato API uses the same workflow.

Four controlled glass and fabric cases compared the exported alpha and the recovered colors over light and dark backgrounds. Partial-alpha mean absolute error fell from 0.589–0.626 to 0.062–0.117. Both backgrounds improved on all four cases. The first aligned reference test showed a visible textured imprint. Using changes in the aligned backing estimated the local transmission and reduced the measurable checkerboard imprint by 88% in the sampled clear interior. Desktop and API exported identical PNGs. Native, PSD and PSB reopened with editable masks and retained the same PNG bytes. One Undo restored each input exactly. The exported PNGs also matched across Debug, optimized Apple Silicon and optimized Intel under Rosetta. The optimized Apple Silicon prepared edit ran in 0.15 seconds on the 1,536 × 1,152 aligned test image.

The four cases use independently generated scalar alpha masks. The recovered glass still has some edge tint and near-opaque coverage errors. The photographic GT03 case from the Rhemann et al. CVPR 2009 matting dataset exceeded the smooth-background limit. The tool asked for an aligned backing, which that photographic input archive lacks. Single-image recovery against complex backgrounds, physical refraction and exact Photoshop behavior remain open. [Matting benchmark](https://static.alphamatting.com/datasets.html)

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-720) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_720.md).

## 2026-11-23 — Step 719 — Review related shadows and reflections before removing them

The Remove processing menu can find shadows and reflections around a marked object using two optional models on Apple Silicon with macOS 26 or later. The canvas shows the reviewed object and each enabled effect. Use the checkboxes or the Add and Subtract brush to refine coverage. Apply creates a correction layer with one Undo. The Photato API shares the same review and edit.

Two licensed photos checked a waste-bin shadow and a vehicle reflection. The first masks left a dark silhouette in each photo. Testing wider masks showed how much overlap was needed and where the review started to touch an unrelated effect. The smaller final margins removed the silhouettes and left the designated neighboring areas and all pixels outside the edit exact. The editor and authenticated API returned equal review masks and rendered RGBA8 bytes on both photos in each Apple Silicon configuration. One Undo restored each original document exactly. The repaired PNGs also match byte for byte across those two configurations.

The vehicle photo also suggested a shadow. The test deselected it before applying. Some grass texture remains soft and the repaired water shows slight color artifacts. Footprints, smoke, steam, water wakes, Adobe’s separate Enhance action and live Photoshop output comparisons remain open. Adobe documents a cloud provider for this feature. The optional Photato models run locally.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-719) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_719.md).

## 2026-11-21 — Step 718 — Use on-device Generative Remove from the brush and API

The Remove brush can use a configured LaMa512 model on Apple Silicon with macOS 26 or later. Generative AI on requires the device model, and Auto can select it for eligible documents. Separated or wide marks use localized repairs and commit in one Undo. Adjacent-edge brush strokes can enclose a corner. The desktop and Photato API share the selection, target, mark geometry and prepared edit.

The on-device model repaired two copies of a photograph in a 12,000 × 9,000 document. All rendered copies were byte-identical in Debug and optimized Apple Silicon. Every sampled unmarked pixel stayed exact. The authenticated API made the same document as the editor, and one Undo restored the source. An independent test used known fill samples to check two distant marks on a sparse 300,000 × 300,000 canvas with both current-layer and transparent correction-layer output. Other tests cover corner closure, blending across repair boundaries, mandatory model failure behavior and native menu availability. The optimized Intel app retained traditional Auto and rejected Generative AI on under Rosetta.

The photo’s repaired grass remains softer than the surroundings. Photoshop 27.2.0 identified itself but its editing controls were unavailable for the comparison. Automatic removal of related effects, cloud Remove processing, the Adobe Execute Actions descriptor and exact Adobe pixels remain open. The 300,000-pixel check used sparse storage and known fill samples.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-718) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_718.md).

## 2026-11-21 — Step 717 — Review and remove general distractions

Remove → Find distractions → General distractions gives you a review before it changes the image. Choose which of the six categories to apply, adjust overlay opacity and refine the marks with the brush. Apply uses the selected raster or a new correction layer and records one Undo. The Photato API shares the same review and edit.

The reviewer marked bins in two independent photographs. A sampled point on the neighboring bench stayed outside the first mask. Traditional fill and optional Apple Silicon LaMa512 fill changed only selected-mask pixels. One Undo restored each original. The authenticated API produced the exact same document as the editor with the real model on Footpath. The tests cover category-only preview, ordered brush refinement, the current selection, layer output and source sampling. The optimized Intel slice also completed the Footpath workflow under Rosetta with traditional fill. The native detection returned one fewer vegetation mark on that run.

The bin sample retained a mounting post, and a strong cast shadow remained in the Footpath photo. Classification still depends on the scene. General distractions uses the 16-megapixel Remove canvas limit. The explicit Generative AI On mode, byte-exact Photoshop output and the Adobe Execute Actions descriptor remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-717) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_717.md).

## 2026-11-21 — Step 716 — Remove extended wire and cable runs in one edit

The Remove tool’s Find distractions menu can remove extended wire and cable runs in one undoable edit. Photato can edit the selected raster or create a transparent correction layer, and the current selection continues to protect pixels. The Photato API uses the same prepared Swift edit and history.

The desktop and authenticated API produced the same document and one Undo restored the original. A 4,200 × 4,000 layered fixture processed beyond the old manual Remove limit. Four synthetic controls preserved all samples more than two pixels from the annotated wires. The repaired wire regions averaged less than two RGB8 levels of error per channel against known clean artwork. Three original-resolution photographs preserved all 1,324,130 checked roof, moon and tower pixels. The Apple Silicon and Intel results matched all 192,426,240 decoded RGBA bytes across the seven examples. A selected-region correction reopened with both raster layers and the same composite in Photato, PSD and PSB. The wider path restored all 6,656 known wide cable samples in the detector fixture without marking its horizon or short trim.

Appearance depends on the scene. Some of the moon photo’s darker fragments and the pylon’s faint wires still need manual cleanup. Camera edges, very wide or short structures, and heavily occluded cables need broader testing. Exact Photoshop wire output, the Adobe Execute Actions descriptor, General distractions and Generative AI On for Remove remain open.

[Development record](../PhotoCraftSwift/docs/DEVLOG.md#dev-step-716) · [Qualification](../PhotoCraftSwift/docs/SOURCE_PUBLICATION_716.md).

[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Next page](part-08.md)
