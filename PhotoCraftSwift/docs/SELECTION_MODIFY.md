# Modify selections and Reselect

Select → Modify now binds Border, Smooth, Expand and Contract to native dialogs with numeric amount, Apply effect at canvas bounds, OK, Cancel, progress and errors. Border accepts1–200px; the other operations1–100px. The factory Reselect item retains Shift-Command-D. Photoshop 2026 defines the target; the native analytical formulas and canvas-bound option/defaults are not yet qualified against its exact output/UI.

The independent engine uses a disc neighborhood over GRAY8 selection coverage. Expand takes the maximum, Contract the minimum and Smooth the median. For binary masks, median is strict majority voting as described in Adobe's guide; gray ranks preserve intermediate coverage. Border averages integer coverage differences from disc dilation/contraction at the two radii surrounding half the requested width. This centers odd/even widths without normalized floating-point cancellation. Exact Photoshop gray/antialias/footprint behavior remains open.

Neighborhood histograms slide across bounded tile halos. Implicit constant planes and sparse support are retained; no full-canvas dense mask or extra side/pixel admission cap is introduced. Canvas-bound behavior is explicit: false clamps virtual samples to edge pixels, true treats virtual exterior coverage as zero. Sparse maximum-dimension tests are storage/admission evidence, not practical maximum dense capacity. The work runs off the main actor and checks cancellation.

Reselect retains the most recently deselected selection in this open document. Rectangular snapshots remain cheap geometry until worker conversion; soft masks retain their immutable coverage. Recall is available when the current selection is absent. Identity/size/read/close changes invalidate it. It is session state, not a new archive field. Layers, source pixels, alpha/masks, color profile and depth are preserved. These commands use one named Undo transaction; Actions stores explicit final coverage using the existing selection format.

The strict selection-only prepared path permits these document-selection edits while a component or mask target is active, preserving that editing target and rejecting pixel edits. Native/API invalid/busy/stale/revoked/canceled work commits nothing. Cancel/read/close release the native draft; source equality is checked before publication. No new canvas tool, modifier action or cursor glyph is introduced.

## API

`selection.modify` takes operation, integer amount and optional atCanvasBounds. `selection.reselect` has no parameters and requires an available retained selection. The catalogue now has 223 typed commands. `selectionModify` state/capabilities expose availability, recall/workspace/busy/errors and parameter/result schemas. Existing shared-document/request limits remain.

```json
{"command":"selection.modify","revision":"<current revision>","parameters":{"operation":"expand","amount":3,"atCanvasBounds":false}}
```

Adobe's published v2 API has no dedicated Modify/Reselect route. Unverified semantic actionJSON descriptors remain unsupported; native coverage Actions is a separate interface. No route or proprietary algorithm equivalence is invented.

## Validation

All 14 new and 323 affected optimized cases pass, with zero failures, unexpected errors or crashes. A separate Python checker verifies 1,920 analytical mask bytes across four odd/even borders. Sparse 300,000 × 300,000/constant-plane admission is tested. Exact Photoshop kernels/gray coverage/defaults/live UI, full-current-suite, supported platforms, maximum dense capacity and physical 60fps remain open.

Tests cover all four operations against a separate naive native disc reference, soft coverage, geometry/empty results, hole/stray cleanup, centered borders, tile seams, sparse dimensions and constant planes, boundary options, validation/cancellation/history/Actions/native archives. Native/API cases cover four dialogs, Reselect for rectangles/soft masks and Undo/Redo/invalidation, three depths, component targets with untouched pixels, actual HTTP equality/state, invalid/busy/stale/revocation, strict rejection of nonselection edits, factory menus/shortcut and read/close/source changes. The Python checker independently builds four owned border masks without the Swift decoder. No live Photoshop acceptance is claimed; last actual app access remains344's locked Mac. Native82/Actions30/all 104 scopes and installed283/private full298/store332 are unchanged.

[Evidence](SELECTION_MODIFY_REFERENCES.json) · [Adobe Expand/Contract](https://helpx.adobe.com/photoshop/desktop/make-selections/refine-modify-selections/expand-or-contract-selection.html) · [Adobe Smooth](https://helpx.adobe.com/photoshop/desktop/make-selections/refine-modify-selections/clean-up-stray-pixels-in-color-based-selection.html) · [Adobe Border](https://helpx.adobe.com/photoshop/desktop/make-selections/refine-modify-selections/create-selection-around-selection-border.html)
