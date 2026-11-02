# Move and copy selected pixels

The Move tool (V) now moves selected image content when a drag starts inside an editable RGB raster selection. Multiple selected areas move together. This branch runs before Auto-Select so the selected active content stays the target. Outside-selection dragging, whole-layer movement and existing unlinked-mask positioning retain their prior paths. Other target contexts remain open.

A drag captures the source document, selection, target, background swatch and Option-copy choice. Option duplicates selected content on the same layer; releasing Option during that captured gesture does not change its operation. Current Shift constrains displacement to45-degree directions. Offsets round to whole pixels. Existing guide snapping uses the selection bounds; Command suppresses snapping and Shift-direction priority also suppresses guide adjustment. Move/copy, constraint and effective snap suppression have shared cursor descriptors; stationary modifier changes refresh geometry and feedback without intercepting text controls.

Preview uses the existing bounded1024-side immutable image/contour proxy, coalesced off the main actor. Pointer input does not edit the real document or history. Mouse release reads original samples once and publishes one Move Undo. Move uses no Free Transform handles/options. Escape, tool/focus loss, native read/close, stale originals and revoked work cancel without publishing; a failed Move leaves an error and exits the gesture. Practical physical60fps still needs measurement.

Arrow keys move selected pixels1pixel; Shift-arrows move10. Option-arrows copy, including repeated copies from the last selected duplicate on the same layer. Each completed operation has its own Move history transaction. Key-repeat scheduling/grouping, temporary selection-tool Command-move and whole-layer Option duplication remain unqualified work.

Ordinary layers leave transparent holes on move and retain their source on copy; off-canvas samples and mask coordinates survive. Background moves fill holes with the captured swatch and retain their opaque canvas-sized role; copies leave the source intact. Shared native-plane reconciliation applies to explicit RGB mode documents. Identity/zero-rounded displacement is a no-op. Tiled damage avoids an extra8MP/36MP admission cap; sparse maximum dimensions do not prove practical maximum dense editing capacity.

## API and Actions

`pixels.move` requires layerID/dx/dy. Offsets are finite document pixels, rounded after optional constrain=true. Optional copy duplicates on the same layer. Optional opaque RGBA backgroundColor is valid for Background; omission captures the current native swatch. The operation shares native preparation, history, source/target/revision/busy/stale/revocation guards. Current gesture state/schema/capabilities expose availability, active/copy, canonical dx/dy, preview/commit/error and Background/captured swatch. The API has228 typed commands. Existing layer.move retains whole-layer semantics.

```json
{"command":"pixels.move","revision":"<current>","parameters":{"layerID":"<UUID>","dx":12,"dy":8,"copy":true}}
```

`pixels.transform` also accepts optional copy=true through the same immutable-sample compositor. Native Free Transform Option behavior remains centered scaling; copying is explicit in this API. New Move/copy semantic Actions require34. Old selected transforms/conversion/Background transform steps retain31/32/33 requirements. Native83 is unchanged. No dedicated selected-content move/copy route or unverified actionJSON descriptor is invented for the published Adobe v2 interface; its existing whole-layer/resource operations remain distinct.

## Qualification

All16 new cases pass. Of633 affected optimized cases,632 pass; one strict offscreen opacity-chevron comparison retains one failed assertion. There are zero unexpected errors and no crashes. An independent Python checker verifies3,072 analytical RGBA channels for ordinary/Background move/copy. Sparse300,000 ×300,000 copies are tested. Exact Photoshop pixels/soft overlap/defaults/gestures/cursor art/live UI, key-repeat scheduling, full-current-suite, supported Macs, maximum dense capacity and physical60fps remain unqualified.

The16 new cases cover three depths/native planes, soft/HDR source preservation, integer/45-degree offsets, same-layer/repeated/multiple-area copies, masks/off-canvas/Background clipping, Actions34 and lower-header rejection, invalid/locked/stale/revoked/canceled work, sparse dimensions and independent analytical vectors. Native cases include actual offscreen mouse down/drag/release, active-selection Auto-Select preservation, arrow keys, all16 modifiers/cursor restoration/art, coalesced/bounded previews, lifecycle and actual HTTP/profile/native-archive equivalence. These are native/owned tests, not Photoshop execution. Last actual native Photoshop access349 remains the locked-Mac result. All104 package scopes remain unclosed.

[Evidence](SELECTED_PIXEL_MOVE_REFERENCES.json) · [Adobe movement](https://helpx.adobe.com/photoshop/desktop/make-selections/refine-modify-selections/control-the-movement-of-a-selection.html) · [Adobe same-layer copies](https://helpx.adobe.com/photoshop/desktop/make-selections/refine-modify-selections/create-multiple-copies-of-a-selection-within-an-image.html)
