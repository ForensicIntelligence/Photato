# Selected-pixel Free Transform

**Checkpoint350:** Move/V now moves/copies selected pixels through the shared preview/commit engine, including Shift constraints and Option-arrow copies. pixels.move and pixels.transform copy/state share Actions34; native83 remains. Earlier Move gaps below describe historical349 scope. [Current guide](SELECTED_PIXEL_MOVE.md).

**Checkpoint349:** Selected RGB Background pixels now use captured background-color holes, opaque canvas clipping, shared preview/commit/history and Actions33/API. The earlier Background transform gap described below is historical348/347 scope. Other transform targets and full acceptance remain open. [Current guide](BACKGROUND_PIXEL_TRANSFORM.md).

Command-T now enters native Free Transform when an ordinary RGB raster layer has a selection. The same six-mode controls used for boundary transforms move, scale, rotate, skew, distort, project and flip selected image content. X/Y, width/height percentages, angle, interpolation, aspect linking, nine reference positions, arrows, Return/Cancel and effective captured modifier cursors remain shared. Direct Edit → Transform rotations/flips target selected content. Existing Photoshop factory titles, hierarchy and shortcuts are retained.

The original layer and selection remain immutable during the operation. The core engine multiplies original alpha by selection coverage, samples premultiplied RGB/alpha, cuts the selected contribution from its old position and composites transformed content over the remainder. Identity is a byte-preserving no-op. Unmoved native quads return exact identity; retained corner coordinates avoid homography roundoff at reference positions. Nearest Neighbor, Bilinear and Bicubic use the source encoding; raw unit-grid sample copies avoid conversion where source-over allows. Bicubic alpha normalization retains unassociated color when alpha overshoots. These are native formulas; exact Photoshop interpolation and soft-overlap semantics remain unqualified.

Storage expands in the layer's existing coordinate frame and retains original pixels outside damage, hidden RGB and off-canvas content. New transformed pixels beyond the canvas remain in layer storage; the selection mask clips to the canvas. Raster/vector masks remain at their existing document positions. Sparse support and bounded tile regions avoid a new 8MP/36MP admission cap. Virtual interpolation support may exceed a source raster by a few pixels; admission checks the actual projected storage extent. Existing300,000-side layer storage, projective coordinate/scratch and shared API limits remain. Sparse maximum-dimension checks do not prove practical maximum dense editing capacity.

A source image proxy, at most 1024 pixels per side, supplies coalesced off-main image/contour previews. The canvas draws it at document coordinates while the real document/history stay unchanged. Apply resamples full original samples once and publishes one named Undo transaction only for the matching source. Cancel, read, close, stale revisions and revoked work cannot publish. Commit cancels previews, and canceled preparation cannot restart one or erase a commit error. Physical60fps, high-zoom preview quality and live Photoshop UI acceptance still need measurement.

## API and Actions

`pixels.transform` requires `layerID` and nine row-major homogeneous `matrix` coefficients in document coordinates. Optional `interpolation` is `Nearest Neighbor`, `Bilinear` or `Bicubic` (default). Its state/capabilities/schemas expose selected-pixel availability, active target, shared draft matrix/mode/reference/preview/commit/error fields. The catalogue now has 225 typed commands. Existing `layer.transform` retains whole-layer semantics; `selection.transform` remains boundary-only.

```json
{"command":"pixels.transform","revision":"<current revision>","parameters":{"layerID":"<raster UUID>","matrix":[1,0,12,0,1,8,0,0,1],"interpolation":"Bicubic"}}
```

One Free Transform transaction provides Undo/Redo. Portable Actions record the layer target, matrix and interpolation and replay against the current selection. Action libraries require version31 only when these new steps are present; older operations retain their existing versions and readers accept1–30. Native document82 remains unchanged. No dedicated published Adobe v2 selected-pixel route or unverified actionJSON descriptor is invented.

## Scope and evidence

The initial working branch requires one unlocked ordinary RGB raster layer and composite pixel editing. Background identity/background-color holes, components/other color modes, layer masks, Smart Objects, multi-layer selected pixels, Warp/mesh, animation and video contexts remain major gaps. Layer names do not establish Background semantics. All 104 package scopes remain open.

All 16 new and 424 affected optimized cases pass, with zero failures, unexpected errors or crashes. A separate Python checker verifies 3,072 analytical RGBA channels across four selected-pixel transforms. Sparse 300,000 × 300,000 admission is tested. Exact Photoshop sampling/soft overlap/gestures/defaults/live UI, full-current-suite, supported platforms, maximum dense capacity and physical 60fps remain open.

The 16 new cases cover identity/raw words/no history; hard/soft cut and movement; interpolation/projective and source coordinate frames; existing/new off-canvas samples and mask positions; sparse maximum dimensions; locks/invalid/stale/cancellation; native archives, semantic Actions and Undo/Redo; native image previews and all 16 modifiers/shared factory bindings; three depths/profiles and actual HTTP/native equality; busy/stale/revoked/canceled transactions; read/close and proxy dimensions. The separate Python reader computes inverses and hard selection lifting/compositing over owned16×12 sources. This does not substitute for Photoshop output. Last native access remains344's locked-Mac observation. No new install, private push, archive, upload, review or release.

[Evidence](SELECTED_PIXEL_TRANSFORM_REFERENCES.json) · [Adobe transforms](https://helpx.adobe.com/photoshop/desktop/crop-resize-transform/resize-adjust-resolution/transform-images-shapes-and-paths.html) · [Adobe movement](https://helpx.adobe.com/photoshop/desktop/make-selections/refine-modify-selections/move-selection-or-selection-border.html) · [Adobe clearing](https://helpx.adobe.com/photoshop/desktop/make-selections/refine-modify-selections/delete-or-cut-selected-pixels.html)
