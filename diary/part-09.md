[Latest entries](../DEVELOPER_DIARY.md) · [Archive index](README.md) · [Next page](part-08.md)

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
