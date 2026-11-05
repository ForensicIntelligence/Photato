# Arrange selected layers

Checkpoint422 adds Bring to Front, Bring Forward, Send Backward, Send to Back and Reverse to the existing Layer > Arrange menu. The first four retain the captured factory Command/Shift-Command bracket shortcuts. Reverse has no factory shortcut. These commands move complete selected group subtrees within their own parent, preserve the order of selected siblings for motion, and keep Background at the bottom. Reverse exchanges selected positions. Selecting a parent and its child moves the parent subtree once.

The operation preserves layer IDs, parent IDs, layer fields and exact stored samples. It does not expand spatial links to additional layers. Native editing prepares off the main actor and commits one Undo after validating the document/session and selected targets. Edge/no-op requests add no history. Background and fully locked selected roots or ancestors must be converted/unlocked first. All original L01 requirements remain in the major stillneeded pass.

## Photato API

Use the existing authenticated, explicitly shared document service and its current revision. The new typed operation is `layers.arrange`:

```json
{
  "command": "layers.arrange",
  "revision": "<current document revision>",
  "parameters": {
    "layerIDs": ["<layer UUID>", "<another layer UUID>"],
    "operation": "bringToFront"
  }
}
```

`operation` accepts `bringToFront`, `bringForward`, `sendBackward`, `sendToBack`, or `reverse`. Supply distinct existing UUIDs. State includes `layerStackOrder.selection` and per-operation `available` flags for the native selection; capability/schema discovery documents the contract. Explicit API targets need not change the native selection. Invalid parameters return400, missing targets404, busy/stale/revoked work409 and unavailable/locked contexts422. Existing service admission, revision, cancellation and resource budgets still apply.

## Actions and Adobe interface

Recorded operations retain semantic layer targets and require Actions48. Older operations keep their earlier minimum versions, including Gradient Fill47. The native document archive stays86.

The published Adobe `POST /v2/create-composite` MoveLayer operation uses the same native stack/relocate primitives within an isolated job. A layer is referenced by its unique name or retained signed32-bit PSD layer ID. Placements supported here are top, bottom, above, below and into, with referenceLayer required for the last three. Complete groups travel with children. Container-only group movement (`shouldIncludeChildren:false`) and top/bottom with an explicit referenceLayer are rejected as unsupported. This is partial contract support, not complete Adobe service conformance. No relative Arrange actionJSON event or new Adobe endpoint is invented.

## References and qualification

Adobe [reorder help](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/transform-manipulate-layers/reorder-and-move-layers.html), updated28September2026, describes stack motion, selected-layer reversal, parent-group limits and the Background boundary. The [published API reference](https://developer.adobe.com/firefly-services/docs/photoshop/api/photoshop-v2/) points to a schema URL that currently returns404. Its official AdobeDocs repository remains accessible: the four relevant schemas match the pinned contract exactly at this checkpoint. Fetch results and source hashes are retained in the422 run.

The owned reference generator places selected items at independently calculated target ranks and fills unselected positions in their original order. It covers310 sibling-subset/Background combinations, exercised at all three RGB depths. These are local algorithm/retention checks, not Photoshop-produced fixtures or proof of matching Photoshop pixels. Current physical Photoshop mixed-parent/lock/clipping/timeline behavior and full L01 acceptance remain open. Layer filtering/isolation and extended empty-layer cleanup remain substantive missing work, before D01 or minor/cleanup passes.

Build and test qualification is recorded in `LAYER_STACK_ORDER_422.json` when the current attempts are terminal.
