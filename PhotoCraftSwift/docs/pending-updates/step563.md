<a id="dev-step-563"></a>

## 2026-11-18 — Record and replay Quick Mask Actions

A recorded Action can enter Quick Mask, paint with Brush or Pencil, change mask options, fill, invert or filter the plane, and exit. Entry starts from the destination document’s selection, and exit returns the edited coverage to the selection. The complete replay uses one Undo. [Adobe Quick Mask](https://helpx.adobe.com/photoshop/desktop/create-masks/layer-masks/create-a-temporary-quick-mask.html) · [Adobe tool recording](https://helpx.adobe.com/photoshop/desktop/automate-tasks/automation-settings-and-presets/record-tools-in-actions.html).

The Actions panel supports recording while Quick Mask is active. Play is available there for an Action that starts with a Quick Mask step and stays on that target until an explicit exit. The worker checks the visibility of the original mask at each editing step and the desktop and HTTP paths recheck it before commit. A mask made by an exit and re-entry uses the normal visible default. A hidden mask can still be filtered.

Batch and Image Processor carry the visibility of an open source with its snapshot. File sources use the normal visible default. The tests cover both display indications, empty and explicitly full selection origins, a visibility change before commit, an invalid target, and replay on copies with different starting selections. New Quick Mask records use Action version 69. The reference Mac was locked. Live Photoshop Action behavior, pixel equality against Photoshop for the complete workflow, and a live check of the Actions controls remain open.

All 558 selected checks passed in Debug, optimized Apple Silicon and Intel under Rosetta. On both architectures, 24 Quick Mask sequences and 24 older Fill Action encodings matched build 562 byte for byte. Both slices of the macOS 14+ universal archive passed offscreen checks. [Qualification](SOURCE_PUBLICATION_563.md).
