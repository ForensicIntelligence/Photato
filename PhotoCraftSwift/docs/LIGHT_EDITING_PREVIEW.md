# Light adjustment previews during painting

Checkpoint 441 adds a presentation-only pause for Light layers that use Highlights or Shadows while a lower layer is being painted or retouched. A notice appears in the document tabs and Properties. Finishing or cancelling the stroke restores the full adjustment.

The display projection substitutes identity Light settings and Normal blending while retaining visibility and clipping relationships. Hiding the layer was rejected after a regression showed that it also hid attached clipped layers. The real document, parameters, masks and layer IDs are retained. Incremental brush/retouch sessions and fallback paint preparation sample the original document; only the resulting display snapshot is projected. Prepared edits, saved files, API rendering and final pixels use the full adjustment. Changed strokes create their usual single Undo; no-op strokes do not gain an artificial history entry.

The structural plan follows visible stack order, isolated/pass-through groups and clipping boundaries. Whole Light layers pause when their Highlights or Shadows are active. Light layers using only Exposure, Contrast, Whites or Blacks remain live. Clarity/Dehaze layers use their existing behavior. Static RGB layer/mask painting and retouch gestures are included; selection, auxiliary-channel, adjustment-brush and Timeline edits do not use this path. Transform, type and other live-edit contexts remain open.

## Optional API

The existing document-state response now contains `lightPreview`:

```json
{
  "paused": true,
  "pausedLayerIDs": ["<Light layer UUID>"],
  "editingLayerIDs": ["<paint target UUID>"],
  "phase": "painting"
}
```

`phase` is `idle`, `painting` or `retouching`. An active gesture can have `paused:false` when it has no affected Light layers. State is read-only. `/v1/capabilities` exposes its schema and policy under `modernAdjustments.interactivePreview` and `stateSchemas.lightPreview`. No command, Adobe endpoint, document format, Actions archive or preference is added. Existing API revision tokens include preview/view changes; clients refresh state after native interactions. Reading this state does not create an edit.

## Verification

The focused Debug run passes 43 methods, including nine new methods. Cases cover original versus projected images, exact clipped-red coverage, Multiply bypass, group/clipping/hidden/order contexts, incremental local damage, 8/16 final command results, native Brush/Pencil/Eraser and masks, nine retouch tools, Cancel/Undo, replaced sessions, selection exclusions and HTTP/schema/guard behavior. The same 43 optimized methods pass on Apple Silicon and under Rosetta, including all nine new methods. Universal macOS 14 packaging, signature and extracted ZIP verify. [Evidence](LIGHT_EDITING_PREVIEW_441.json).

These tests verify selected native paths and preservation of final results. They do not establish interactive 60 fps, exact Photoshop timing/visuals, occlusion/zero-mask policy, physical Intel/macOS 14 behavior or all editing contexts. All earlier full-suite and numerical failures remain recorded.

The full A04 scope remains open: editable modern PSD/PSB descriptors, actual Light version switching, larger neighborhood processing, other live edits and independent output/default/ICC/platform qualification. The existing “Use legacy Brightness/Contrast” action replaces the layer type with reset controls; it is not implementation of Photoshop's Light version menu.

## Reference

Adobe's [Light adjustment guide](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/color-adjustment-fill-layers/adjust-image-lighting-with-light.html), updated 9 September 2026, describes pausing Light while editing below when Highlights or Shadows are used. It does not specify the numerical kernels, PSD descriptors or every contextual pause rule. Implementation is native Swift over the existing compositor and stroke owners. No Adobe source or artwork was copied. Live Photoshop reference access remains unavailable pending the earlier human unlock request.
