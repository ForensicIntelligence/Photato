# Editing groups of video keyframes

Open a video Timeline and expand **Clip and keyframe properties**, then the layer and its property’s key list. Check the keys to select them. Selection can span properties and layers. The Timeline’s **Keyframes** menu contains Delete, Copy, Paste, Select All, Deselect All, Linear Interpolation and Hold Interpolation. The key-list menu offers the same actions, with Select All scoped to that property. Selection and Copy do not add content history.

Copy retains an immutable snapshot of the selected values, interpolation and spacing in an application-local clipboard. Move the playhead, select the destination layers and choose Paste. The earliest copied key starts at the playhead. One copied layer can populate several destinations; several copied layers map to the same number of selected destination layers in document order. Matching property/time keys are replaced; unrelated keys remain. New keys receive fresh IDs, while replaced destination keys retain theirs. The pasted keys become selected.

The inspector’s Move and Duplicate buttons apply a time offset in seconds to the selected group. Moving first removes the selected source times, so selected keys can move through one another’s former positions. An occupied, unselected destination time rejects the whole operation. Delete and interpolation changes also apply atomically. Content and Visibility use Hold. Position and Transform remain alternative geometry tracks. Locks and existing layer, timing and metadata budgets still apply. Paste and Duplicate check final key budgets before allocating copies.

Each content edit is one Undo transaction. A native Photato archive retains the resulting keys and values; view selection and the clipboard are temporary. The native clipboard works across open documents without reading or replacing the operating-system clipboard. Colour/content keys require matching document depth and working profile. Profile conversion during paste, external clipboard interchange, graphical marquee/group dragging, complete PSD/Actions animation interchange and full SP01 remain outstanding.

## Optional API

All operations use the existing `video.keyframe` command at `POST /v1/documents/{id}/commands`, with the current document revision. Existing enable/disable/set/delete/move/interpolation operations remain unchanged. The new operations are:

| Operation | Parameters |
| --- | --- |
| `select` | `keys: [{layerID, keyframeID}]`; optional `selectionMode`: replace, add, toggle or remove |
| `selectAll` | Optional `layerID` and `property` |
| `deselectAll` | None |
| `copy` | None; captures the current selection |
| `paste` | Optional ordered `layerIDs`, `time`, `sourceDocumentID` and `sourceRevision` |
| `deleteSelected` | None |
| `moveSelected` / `duplicateSelected` | `delta` in seconds |
| `interpolateSelected` | `interpolation`: linear or hold |

Document video state reports `keyframeSelection` and `keyframeClipboard` metadata (count, layer count and original earliest time). HTTP Copy and Paste require document-transfer permission. The API clipboard is separate from the native clipboard and bound to the actual share, API session, transfer grant and document lifecycle. It never reads a user’s native clipboard. Revoking and restoring permission does not restore an old clipboard grant.

Paste defaults to the active destination layer and playhead. To use another explicitly shared document’s API clipboard, supply its share ID as `sourceDocumentID` and its current `sourceRevision`. Source sharing, revision, lifecycle, permission grant and clipboard identity are checked again before the prepared edit commits. Ordinary edits after Copy do not alter the copied snapshot. Invalid parameter combinations, busy documents, stale revisions, revoked sources, unsupported property/profile contexts and collisions reject without partial content changes.

Both API interfaces remain supported independently. Adobe’s pinned Firefly v2 resource-job contract has no interactive keyframe-clipboard endpoint; no Adobe route or proprietary animation descriptor was invented. Native format 92, Actions 60 and 271 typed commands are unchanged. No new main-menu shortcut or tool-modifier action was added.

[Build 518 evidence](KEYFRAME_GROUP_EDITING_518.json) records the selected tests and live checks. Installed Photoshop 2026 supplied the observed menu and single-layer copy/paste reference. Native shifted-curve/pixel and archive tests are regression evidence, not a claim of Photoshop pixel equality. Multi-layer mapping, collision/default/shortcut fidelity, physical supported platforms, dense capacity, performance, full interchange and all original SP01 acceptance remain open.
