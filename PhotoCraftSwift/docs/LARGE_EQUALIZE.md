# Large-document Equalize

Use **Image > Adjustments > Equalize** on an unlocked ordinary pixel layer. With a selection, the existing dialog offers selection-only editing or whole-image editing based on selected statistics. Apply creates one Undo step. Cancel leaves the document unchanged. Selection, alpha, layer identity and existing transform/mask metadata are retained through the shared transaction.

The Equalize path now accepts the native canvas limit of 300,000 pixels per side, up to 90 gigapixels. Histograms use 256 fixed bins and exact implicit-sample counts. Stored edge-tile padding is excluded. Output uses paged pixels and the existing selection, quantization and geometry rules. Tests cover maximum implicit rasters and sparse coverage at every native depth; they do not establish dense maximum performance or Photoshop depth/mode support.

Large selected-area dialogs use an overview bounded to 2048 pixels on the longer side. The dialog labels it as an overview and disables its full-resolution zoom controls. Full-resolution output is applied; inspect that output in the document. A full-resolution interactive dialog viewport remains stillneeded. Other classic tone families retain the 8,388,608-pixel preparation limit.

The existing optional API operation remains `tone.apply`, with `kind: "equalize"` and optional `settings: {"equalizeEntireImage": true}` in the normal revision-protected command envelope. Native controls, API and portable Actions use the same command and history path. `maximumPixelsByKind` advertises the Equalize limit; the older `maximumPixels` field retains its previous general-family bound for compatibility. Native workspace state exposes `overviewOnly`. Typed commands 250, native archive 86, Actions 49 and settings 4 are unchanged. No menu identity or shortcut was added.

The existing Adobe v2 execute-actions route remains available for its qualified operations. Equalize ActionJSON/UXP descriptor mapping and its exact defaults/output are still unqualified. No new endpoint or descriptor is invented for this change.

Checkpoint 430 passes 30 focused Debug cases and the same 127 selected optimized cases on ARM64 and Intel under Rosetta, including all 38 new methods from checkpoints 426–430. Eight methods are new here. Small outputs match the retained pre-change array engine, analytical histogram vectors and canonical display pixels. The first bounds defect, slow preview profile and failed constant-preview memory assertion were preserved before repairs; old expected pixels and tolerances were not changed. Both macOS 14 binary slices, ad-hoc signature and ZIP extraction checks pass. These are scoped development results, not full-suite, physical-platform, 60fps or Photoshop-parity proof.

Brightness/Contrast, the other large tone processors and all remaining A03 scope stay major stillneeded. [Evidence](LARGE_EQUALIZE_430.json).
