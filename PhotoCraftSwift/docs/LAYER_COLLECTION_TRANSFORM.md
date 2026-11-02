# Multi-layer and group Free Transform

Select several whole layers or a group, then use Command-T. A shared bounding box and reference point now serve the selection. Scale, Rotate, Skew, numeric X/Y/W/H/angle, nine reference positions, fixed rotations/flips and Shift/Option controls use the existing native transform interface. Parent-plus-child selections normalize to root subtrees, so a child is transformed once. Return applies; Escape cancels. Undo/Redo retains valid layer selections when the active layer identity is unchanged; structural history changes keep the existing active-layer fallback.

The operation applies a common affine matrix to each member from the immutable source. Layers keep their order, hierarchy and identifiers. Type and shapes stay editable; Smart Object source bytes stay intact. Linked masks follow the transform; unlinked masks retain document placement. Style parameters are retained without automatic effect scaling. Position locks and unsupported member geometry reject the complete transaction before publication. Whole-layer projective Distort/Perspective, Warp and repeat remain open requirements. Their collection controls/modifier cursors are unavailable and do not invoke another operation. This is an implementation limitation, not a claim about Photoshop's permitted combinations.

The preview uses the shared off-main coalesced document proxy (at most1024pixels per side). The real document/history stays unchanged while adjusting. Apply uses original samples and one Free Transform Undo; cancellation, changed source/selection, read/close and focus/tool loss prevent stale publication. Single ordinary layers keep their existing path. No new8MP/36MP admission cap is added; existing type/Smart/mode/format/scratch/API budgets and practical maximum dense capacity remain separate gates.

## API and Actions

`layers.transform` accepts layerIDs, a nine-value row-major document-coordinate matrix and optional interpolation. The matrix must be affine; projective matrices explicitly return422. Native scale/rotate/skew/fixed transforms and this API share DocumentGeometry, preparation, history and validation. State/schema/capabilities expose targets, normalized roots, supported modes, affineOnly, preview/commit/error, matrix and reference. There are231commands.

```json
{"command":"layers.transform","revision":"<current>","parameters":{"layerIDs":["<UUID>","<UUID>"],"matrix":[1,0,24,0,1,16,0,0,1],"interpolation":"Bicubic"}}
```

New semantic collection Actions require37 and resolve portable layer references. Older operation minimum versions remain; falsely labeled36files are rejected. Native83 is unchanged. Existing Adobe per-layer/resource transforms share DocumentGeometry and retain their schemas/job lifecycle. The pinned contract has no new joint document-coordinate affine-matrix route; no route or unverified actionJSON descriptor is invented. Published contract gaps remain open.

## Validation and remaining work

All 16 new cases pass. Of 851 affected optimized cases, 850 pass; one strict offscreen opacity-chevron comparison retains one failed assertion. There are zero unexpected errors and no crashes. An independent Python checker verifies 5120 analytical RGBA channels across four transforms. Sparse 300,000 × 300,000 layers are tested. Exact Photoshop samples, collection bounds, kernels, defaults and live UI, the full current suite, supported platforms, maximum dense capacity and physical 60fps remain unqualified.

The16new tests cover three depths, common transforms, root deduplication, masks/style/type/shape/Smart source preservation, locked descendants/Background/invalid/selection guards, history/Actions37/native archives, actual offscreen pointer/Return, all16modifier modes and disabled projective controls, API/profile/interpolation consistency, stale/busy/revoked/canceled/changed selections, lifecycle, bounded/coalesced previews, sparse dimensions and analytical composite outputs. These are owned/native checks, not Photoshop execution.

Adobe's current documentation supports transforming multiple selected layers and the common Free Transform controls. Exact Photoshop bounds/defaults/gesture/output/cursor behavior still needs direct comparison. Last actual native access349 reported the Mac locked; no repeated unchanged poll. Projective collection/type/shape transforms, Warp/repeat, persistent linked-layer relationships, selected/multi-layer pixel and mask/color/ink targets and other major workflows remain. All104full package scopes remain unclosed. The prior opacity snapshot and11historical rendering/interchange gates remain. Installed283/private source298/store archive332 are unchanged.

[Evidence](LAYER_COLLECTION_TRANSFORM_REFERENCES.json) · [Multiple layers](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/transform-manipulate-layers/select-layers.html) · [Scaling controls](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/transform-manipulate-layers/scale-layers-in-photoshop.html) · [Free Transform](https://helpx.adobe.com/photoshop/desktop/crop-resize-transform/resize-adjust-resolution/transform-images-shapes-and-paths.html)
