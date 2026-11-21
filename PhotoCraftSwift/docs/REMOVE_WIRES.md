# Remove wires and cables

Choose **Remove** in the J tool group, then **Find distractions → Wires and cables**. Photato detects extended cable runs and repairs them in one undoable edit. The progress control’s Cancel button and Escape discard work before it is applied. If the image has no detected cables, the document and history stay as they were.

**Sample All Layers** analyzes the visible composite. Turn it off to analyze the selected raster. **Create New Layer** places a transparent raster patch above the active layer and its clipping stack. Otherwise Photato edits the active raster, respecting layer and transparency locks. Both outputs respect the active selection and leave it editable. **Remove after each stroke** applies to hand-drawn strokes. Wires and cables applies directly from the menu.

The detector looks for a narrow band with matching contrast on both sides, supported along a continuous path. It samples an overview of up to 1,536 pixels on the longest side, then reconstructs the selected regions at native document resolution. No model installation or network request is needed. The result works best on extended visible runs, particularly against open sky. Faint, short, tightly clustered or partially obscured cables can remain, and other thin structures can resemble cables. Use Undo if the result needs manual refinement. General distractions and Generative AI On for the Remove tool remain open.

## Photato API

Send `retouch.remove` to the shared document’s authenticated `/v1/documents/{id}/commands` endpoint with its current revision and `{"operation":"removeWires"}` as the parameters. It uses the same window options and transaction as the toolbar. `removeTool.wiresAvailable` indicates a suitable target with no pending marks, and `removeTool.removingWires` reports work in progress. A successful response includes `removeWiresResult.candidateTracks` and `removeWiresResult.applied`. Track counts refer to connected detections, so one physical cable can contribute several tracks. A no-change result returns `applied:false` and creates no Undo state. Existing `cancel`, sharing and stale-revision checks apply.

The pinned Firefly Photoshop v2 contract has no dedicated wire removal route. Photoshop’s Execute Actions descriptor and matched Adobe image outputs remain unqualified. [Adobe desktop workflow](https://helpx.adobe.com/photoshop/desktop/repair-retouch/remove-objects-fill-space/remove-wires-people-distractions.html) · [Adobe API reference](https://developer.adobe.com/firefly-services/docs/photoshop/api/photoshop-v2/)
