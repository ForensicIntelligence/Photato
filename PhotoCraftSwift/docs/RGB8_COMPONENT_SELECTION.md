# RGB8 component selection

The Channels panel can select pairs of ordinary RGB8 color components. A plain row click selects one component; Shift-click changes the selected set. Pair selection uses the existing component editing engine for Fill, Invert, Brush/Eraser and supported filters. Untargeted samples and alpha stay unchanged. This extends the selected C01 path; the full channel workflow remains open.

The RGB row selects composite. The existing `channel.target` singleton API and UI representation are preserved. The existing `mode.channel.select` also accepts ordinary RGB8 indices: 0 Red, 1 Green, 2 Blue. Empty or all three indices canonicalize to composite; one index uses the original singleton selector; two indices retain a pair. The current row policy treats composite as all selected and retains the final individual target instead of interpreting zero selected targets as composite. Exact Photoshop boundary and mixed-target behavior remains unqualified.

A pair initially displays its selected channels. Later preview/eye operations change visibility independently. The API reports the selected names in `channelTarget`, indices in `documentMode.editingComponents` and actual visible indices in `documentMode.visibleComponents`. `DocumentModeAPI.colorComponentSelection` describes the contract. Selection itself changes no pixels, dirty state, Undo or native-file content. Busy/stale/invalid requests reject; component edits must match the captured selected set. Existing native history and cancellation paths are shared. No new typed command, route, Adobe descriptor or file-format version is added.

For a shared document, POST the usual command envelope to `/v1/documents/{id}/commands`:

```json
{"command":"mode.channel.select","revision":"<current revision>","parameters":{"components":[0,2]}}
```

This selects Red and Blue. `channel.fill` then applies its existing neutral value/opacity operation to both; `mode.channel.edit` and `paint.stroke` retain their existing contracts. The existing `channel.target` command still selects a single named channel.

All eight new development tests pass. The first focused run passes 103 of 104 cases; its only failure is the existing maximum-CMYK HTTP timeout, which also reproduces on preserved build 405. Additional component/view and painting cases pass. Across the current attempts, 121 distinct IDs pass, which is not a single passing suite. Two broadened clipboard runs terminate by signal 10; the same started ID also terminates on preserved 405. Those failures are retained, without changing limits or fixtures. Normal optimized universal qualification remains batched for a stable milestone.

The actual native app passes a singleton row/shortcut/Invert/Undo/Redo/Quit regression check on an owned document. Physical Shift-click pair selection was not observed: the attempted focused Shift-Space produced no selection change. The shared dispatch function and HTTP path are tested separately. Photoshop currently exposes an unnamed blank window, so current live behavior and pixel equivalence are not claimed. Public [Adobe channel guidance](https://helpx.adobe.com/photoshop/desktop/adjust-color/hdr-and-channel-manipulation/manage-channels-in-the-channels-panel.html) documents Shift-click selection. See [the retained evidence](C01_RGB8_SELECTION_406.json) for commands, failures and remaining acceptance.
