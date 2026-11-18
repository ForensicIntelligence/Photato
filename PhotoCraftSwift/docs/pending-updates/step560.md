<a id="dev-step-560"></a>

## 2026-11-18 — Add Clear to Edit Fill and Stroke

The Mode menu in Edit Fill and Stroke now has Clear. The dialog enables it on ordinary, unlocked 8- or 16-bit RGB pixel layers and disables Preserve Transparency during the operation. Stroke still offers Inside, Center, and Outside. The Clear transaction keeps the layer extent and selection and can be undone in one step. [Adobe blending modes](https://helpx.adobe.com/photoshop/desktop/repair-retouch/adjust-light-tone/blending-mode-descriptions.html) · [Fill](https://helpx.adobe.com/photoshop/desktop/apply-painting-techniques/fill-objects-selections-layers/fill-selection-layer-color.html) · [Stroke](https://helpx.adobe.com/in/photoshop/desktop/apply-painting-techniques/fill-objects-selections-layers/stroke-selection-layer-color.html).

The paint engine uses the existing alpha-removal operation with opacity and coverage. In Photato, Pattern Fill Clear also uses the pattern's alpha. The small-canvas tests check feathered coverage and moved layer bounds. The uniform case can clear a sparse 300,000-pixel-square layer without allocating a dense image. Exact Photoshop Clear pixels, pattern alpha behavior, and live dialogs still need a controlled desktop comparison. The reference desktop was locked during this step.

The existing Photato Fill and Stroke commands now accept Clear. Action version 66 records solid and patterned Clear edits for replay against the active layer of another document. The pinned Adobe endpoint list still has no separate destructive Edit Fill or Stroke endpoint. [Adobe Photoshop API v2](https://developer.adobe.com/firefly-services/docs/photoshop/api/photoshop-v2/).

All 522 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. On each architecture, 264 existing Fill, Stroke, and Path Clear pixel buffers and the legacy settings JSON matched build 559 byte for byte. Both slices of the macOS 14+ universal archive passed offscreen checks. [Qualification](SOURCE_PUBLICATION_560.md).
