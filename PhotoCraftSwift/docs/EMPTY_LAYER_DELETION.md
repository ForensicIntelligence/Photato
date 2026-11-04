# Delete All Empty Layers

File > Scripts > Delete All Empty Layers runs the native asynchronous deletion transaction. The optional Photato API command is `layers.deleteEmpty`, with an empty parameter object and the current document revision. `emptyLayerDeletion.canRun` reports current availability; discovery describes scope and limitations. The API is disabled until the user enables it and shares a document.

```json
{"command":"layers.deleteEmpty","revision":"<current revision>","parameters":{}}
```

The current implementation examines stored alpha in ordinary unmasked raster layers. It ignores hidden RGB and does not infer emptiness from visibility, opacity, masks or placement outside the canvas. Plain groups made empty by eligible deletions are removed recursively. Surviving data, active layer and layer selection are retained. A change has one named Undo entry; a no-op adds no history and does not change dirty state. The existing API view revision can advance when the canvas redraws. Analysis uses existing bounded sparse surface storage, with no new megapixel cap.

Clipping bases, locked layers or ancestors, Background, masks/effects, retained source tags, native-mode storage, Smart Objects, temporal content, type, shapes, fills, adjustments, artboards and frames are preserved. Timeline, ink, channel-only and restricted-mode documents are unavailable. Full Photoshop lock/group/last-layer and extended-content behavior remains unqualified. These are open requirements, not a claim of full command or package parity.

Native and HTTP requests share preparation, history and commit validation. Invalid parameters, busy or stale requests must leave the document unchanged. Existing Actions store resolved deleted layer targets; automatic empty-layer re-evaluation during later playback remains open. Native archive86 and Actions46 are unchanged by this feature.

Adobe documents the [desktop command](https://helpx.adobe.com/ph_fil/photoshop/using/layers.html) and [explicit v2 layer deletion](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2/v1-to-v2/layer-operations-advanced). The automatic empty-layer selector is available only through Photato’s native command and API. The current general Adobe create-composite adapter supports edits and retains a separate deletion gap; Background deletion has separate existing support. No automatic-empty Adobe endpoint is invented or claimed.

[Current evidence and qualification](EMPTY_LAYER_DELETION_403.json). Photoshop menu presence is observed, but attempted reference execution did not produce a verifiable output; it is not an oracle pass. The full current regression suite, physical supported-platform, dense maximum-capacity and sustained60fps gates remain open.
