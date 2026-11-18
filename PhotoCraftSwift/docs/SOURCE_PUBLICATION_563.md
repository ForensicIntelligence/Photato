# Source checkpoint 563

Native Swift 0.3.0, build 563, 18 November 2026. Photato Actions can enter Quick Mask, record Brush and Pencil strokes, and convert the edited mask back to a selection in one undoable Action. Actions also record options, Fill, Invert, and supported filters on the temporary plane. Entry samples the destination selection. Exit preserves the existing rules for empty and explicitly full selections. [Adobe Quick Mask](https://helpx.adobe.com/photoshop/desktop/create-masks/layer-masks/create-a-temporary-quick-mask.html) · [Adobe tool recording](https://helpx.adobe.com/photoshop/desktop/automate-tasks/automation-settings-and-presets/record-tools-in-actions.html).

A visibility check protects the original temporary mask. A later exit and re-entry creates a fresh visible plane. Filters can still run on a hidden Quick Mask. Replay resolves these steps through desktop and HTTP playback, Batch, and Image Processor. Actions 69 stores the new options and temporary strokes. Earlier Action files retain their format requirements.

All 558 selected checks passed in Debug, optimized Apple Silicon and Intel under Rosetta. On both architectures, 24 Quick Mask sequences and 24 older Fill Action encodings matched build 562 byte for byte. Both slices of the macOS 14+ universal archive passed offscreen checks.

The reference Mac was locked. Live Photoshop Action behavior, pixel equality against Photoshop for the complete workflow, and a live check of the Actions controls remain open.

[Development record](DEVLOG.md#dev-step-563) · [Validation evidence](QUICK_MASK_ACTIONS_563.json) · [Frozen source](SOURCE_SNAPSHOT_563.json)
