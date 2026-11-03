# Quick Mask visibility

Checkpoint369 Source02 passes454 affected cases and five new cases on each architecture, with a current universal native eye/brush/Undo check. Photoshop2026 is the reference; full S05/C01 output and platform acceptance remains open.

The Channels-panel eye shows or hides the temporary Quick Mask overlay. It does not execute Q, remove the temporary channel, convert it to a selection or change the editing target. The runtime flag is scoped to the document and temporary-mask IDs, so a newly created mask starts visible. It does not change document pixels, native storage or Undo history.

An owned Photoshop27.2 UI check confirms a separate rule: a brush stroke on a hidden Quick Mask is rejected. Photato's interactive gesture entry, routed stroke and typed channel stroke therefore reject that hidden target until it is shown. Brush controls and modifier semantics stay unchanged. Other hidden-target Fill/filter/tool rules require separate reference checks; no general claim is made for them.

The existing Photato `channel.view` command accepts optional `visible` only for `target: "quickMask"`. State exposes `quickMaskVisible`. The channel-preview resource follows the flag; the ordinary image preview/export remains the composite. Missing masks, invalid arguments, busy edits and stale revisions preserve the document. No new command identity, native archive version, semantic Action or Adobe route is added.

Direct reference: owned live Photoshop checks in `photoshop-quickmask-eye01.json` and `photoshop-quickmask-paint02.json` under the369 evidence run. Adobe's [channel guide](https://helpx.adobe.com/photoshop/desktop/adjust-color/hdr-and-channel-manipulation/channels-in-photoshop.html) describes separate eye visibility and channel selection; its [Quick Mask guide](https://helpx.adobe.com/photoshop/desktop/create-masks/layer-masks/create-a-temporary-quick-mask.html) distinguishes the temporary channel from returning to Standard mode. These pages do not replace the direct hidden-brush check.

The broader C01 scope retains independent component/auxiliary visibility and targeting, temporary pixel/vector-mask rows, per-mode paint/filter integration, eye gestures and factory shortcuts. C01 stays queued while this shared S05 display dependency is repaired and tested.
