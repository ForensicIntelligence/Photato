# Flatten Image

Layer > Flatten Image and the Layers context menu combine visible artwork into one opaque Background layer over white. Hidden layers require confirmation in the native UI. Cancel, cancellation and changed-source checks preserve the original. The full document is rendered even with a pixel selection; the selection is retained. One Undo restores the original editable graph.

Ordinary static RGB stacks use the shared native compositor, including groups, clipping, transforms, masks, type, shapes, adjustments, effects and resolved Smart artwork within its existing feature/resource budgets. Large output uses pages or implicit pixels; committed resolution is not reduced. Integer output is quantized once at document precision from the Float32 working composite. Opaque stored samples retain their bits; the opaque helper resolves implicit samples once and streams allocated tiles rather than scanning every logical pixel.

An aligned, visible, opaque single-layer native RGB/Gray/CMYK/Lab document keeps its numerical source planes and profile. Layered or transparent native component composition is still missing; routing through a display RGB cache would lose out-of-gamut values and ink separations. Indexed/Bitmap/ink and temporal flattening also need their own composition paths. These requirements remain in the full workflow scope. An already single-Background document has no further flatten operation in the current implementation.

Document selection, saved channels, guides, paths, profiles, comps, metadata and libraries remain document-owned. Missing references to removed layers stay observable rather than silently deleting comp or variable definitions. Exact Photoshop handling of those contexts still requires independent qualification. Artboard layers bake through the compositor; the resulting Background uses current canvas coordinates. No layer-specific Smart Object, group, style or mask remains on the new Background.

## APIs and Actions

The Photato operation is layer.flatten with optional Boolean discardHiddenLayers (default false). Hidden layers without explicit true return422; invalid input returns400 and busy/stale/revoked operations retain409 handling. State exposes flattenImage availability, hidden IDs, confirmationPending and confirmation requirements. The native UI, API and semantic Actions use the same source-bound prepared edit and history path. Targeted channel/mask contexts require returning to the composite document target.

The published Adobe flattenImage actionJSON event (FltI) runs through existing /v2/execute-actions and /v1/action-jobs resource jobs. No route is invented. Both interfaces keep isolated resource/job lifecycles and hosted output. Adobe's own v2 migration example contains this event; that does not establish complete descriptor or service equivalence.

Semantic recording/replay requires native Actions43. Older operation minimum versions, including Pattern42 and pixel Fill/Stroke41, remain. Native document version84 is unchanged; Background requires83or84when negotiated over the API. There are236typed Photato commands. Factory menu title/order and the absence of a dedicated factory Flatten shortcut are preserved. No canvas tool or modifier cursor action is added.

## Verification

All 19 new cases pass. Of 312 affected optimized cases, 312 pass; 0 fail with 0 assertions and 0 unexpected errors. There are 0 crashes. Independent checks verify 48 RGBA bytes across three analytical vectors and three PNGs, plus six PSD/PSB headers.

This is a working Flatten Image increment. Layered/transparent native components, palette/ink and temporal flattening still need their numerical/plate/frame compositors. Full Photoshop output/defaults/live UI, complete L02 merge/rasterization, supported platforms, dense capacity and physical60fps remain open. All104complete scopes are preserved.

Tests use owned artwork, native offscreen controls and real loopback HTTP jobs. They do not constitute live Photoshop qualification. The saved source manifest, binary hash and attempt logs bind the results to the tested source. Installed preview283, private full-source backup298 and store archive332 remain unchanged.

[Adobe desktop workflow](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/get-started-layers/flatten-layers-in-an-image.html) · [Official event IDs](https://developer.adobe.com/photoshop/uxp/2022/ps-reference/media/eventcodes) · [Adobe v2 example](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2-beta/v1-to-v2/convenience-apis/side-by-side) · [Evidence](FLATTEN_IMAGE_REFERENCES.json)
