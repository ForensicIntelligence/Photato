<a id="dev-step-561"></a>

## 2026-11-18 — Record Paint Bucket Actions

Start recording an Action, then click with the Paint Bucket. A fill that changes pixels adds a step. The step stores the click in document pixels, the portable layer or mask target, and the bucket options. A patterned fill also saves the pattern and its placement. Option-click color sampling, configuration, and fills that change nothing add no Paint Bucket step. [Adobe tool recording](https://helpx.adobe.com/photoshop/desktop/automate-tasks/automation-settings-and-presets/record-tools-in-actions.html) · [Adobe Paint Bucket](https://helpx.adobe.com/photoshop/desktop/apply-painting-techniques/fill-objects-selections-layers/fill-paint-bucket-tool.html).

Playback samples the destination layer, mask, or visible composite at that point in the Action and applies the current selection. A preceding step can change the sampled image. The tests cover a differently sized canvas, new target identifiers, a long layer name, embedded Pattern Clear after a library replacement, and rollback of the whole Action if the target is unavailable.

The existing `paint.bucket` command records the same recipe as a desktop click. Existing native and HTTP Actions playback share the renderer. Portable Paint Bucket steps use Action version 67. Percentage coordinates, the separate tool-recording toggle, and Adobe Paint Bucket behavior remain open. [Adobe Photoshop API v2](https://developer.adobe.com/firefly-services/docs/photoshop/api/photoshop-v2/).

All 527 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The 240 color-region masks and 18 direct bucket buffers matched build 560 byte for byte on both architectures. Both slices of the macOS 14+ universal archive passed offscreen checks. [Qualification](SOURCE_PUBLICATION_561.md).
