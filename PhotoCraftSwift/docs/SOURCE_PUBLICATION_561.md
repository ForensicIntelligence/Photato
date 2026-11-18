# Source checkpoint 561

Native Swift 0.3.0, build 561, 18 November 2026. Paint Bucket fills can be recorded and replayed in Photato Actions with the saved settings and the playback document’s own pixels and selection. Recording a changing fill saves the pixel coordinate, portable target, color, and tool settings. Pattern fills retain the original pattern and placement. Replay samples the target mask, current layer, or visible composite after any preceding Action steps. [Adobe tool recording](https://helpx.adobe.com/photoshop/desktop/automate-tasks/automation-settings-and-presets/record-tools-in-actions.html) · [Adobe Paint Bucket](https://helpx.adobe.com/photoshop/desktop/apply-painting-techniques/fill-objects-selections-layers/fill-paint-bucket-tool.html).

The desktop and existing `paint.bucket` command record the same recipe. Use the existing Action playback paths. A saved seed outside the playback canvas or a missing target rejects the transaction. New Paint Bucket steps require Photato Actions 67 and use the existing 16 MiB library limit. The published Adobe compatibility endpoints remain separate. [Adobe Photoshop API v2](https://developer.adobe.com/firefly-services/docs/photoshop/api/photoshop-v2/).

All 527 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The 240 color-region masks and 18 direct bucket buffers matched build 560 byte for byte on both architectures. Both slices of the macOS 14+ universal archive passed offscreen checks.

The reference desktop was locked. Exact Photoshop Paint Bucket recording, Allow Tool Recording, ruler-unit behavior, and pixel results still need a controlled comparison.

[Development record](DEVLOG.md#dev-step-561) · [Validation evidence](PAINT_BUCKET_ACTIONS_561.json) · [Frozen source](SOURCE_SNAPSHOT_561.json)
