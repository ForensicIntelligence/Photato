# Source checkpoint 560

Native Swift 0.3.0, build 560, 18 November 2026. Edit Fill and Stroke can erase pixels through the native dialogs, the existing Photato API, and recorded Actions. Choose Clear in the Mode menu on an unlocked 8- or 16-bit RGB pixel layer. Opacity, selection coverage, all three Stroke locations, and Undo use the existing paint transaction. Preserve Transparency is disabled while Clear is selected. [Adobe blending modes](https://helpx.adobe.com/photoshop/desktop/repair-retouch/adjust-light-tone/blending-mode-descriptions.html) · [Fill](https://helpx.adobe.com/photoshop/desktop/apply-painting-techniques/fill-objects-selections-layers/fill-selection-layer-color.html) · [Stroke](https://helpx.adobe.com/in/photoshop/desktop/apply-painting-techniques/fill-objects-selections-layers/stroke-selection-layer-color.html).

The existing `pixels.fill` and `pixels.stroke` commands accept `"mode": "Clear"` without a color. Fill can use a saved pattern and apply its texel alpha. New Clear recordings use Photato Actions version 66. Previous solid, pattern, and Path Fill recordings retain their original version requirements. [Adobe Photoshop API v2](https://developer.adobe.com/firefly-services/docs/photoshop/api/photoshop-v2/).

All 522 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. On each architecture, 264 existing Fill, Stroke, and Path Clear pixel buffers and the legacy settings JSON matched build 559 byte for byte. Both slices of the macOS 14+ universal archive passed offscreen checks.

Exact Photoshop Clear pixels, pattern alpha behavior, and live dialogs still need a controlled desktop comparison. The reference desktop was locked during this step.

[Development record](DEVLOG.md#dev-step-560) · [Validation evidence](PIXEL_EDIT_CLEAR_560.json) · [Frozen source](SOURCE_SNAPSHOT_560.json)
