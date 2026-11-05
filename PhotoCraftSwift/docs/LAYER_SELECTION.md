# Layer selection

Select > Deselect Layers clears layer selection. It has no factory keyboard shortcut. Command-clicking the last selected row also clears selection. A plain click below the final row deselects; modified clicks and drags in that space do not. The unused panel area has a native accessibility action and does not overlay row controls. All Layers gives the resulting selection a valid active layer.

These are view changes: they do not edit pixels or add content Undo, clear Redo or mark the document dirty. The saved active-layer view field can change. Pixel selections and retained channel planes remain intact. Leaving the selected layer clears its mask-only display and layer-owned path target.

The recorder saves an explicit Deselect Layers step in portable Actions format 49. Recording may start or stop with no active layer. A recipe containing only layer selection steps validates every target before publishing the final view and adds no content Undo. A mixed recipe containing pixel/document edits retains the normal prepared transaction. Native document archive 86 is unchanged; these recipes are Photato Actions, not Adobe ATN files.

## Optional API

Use the authenticated command endpoint and current shared-document revision:

```json
{"command":"layers.selection","revision":"<current revision>","parameters":{"operation":"none"}}
```

Operations are `select`, `all`, `none` and `linked`. `select` requires a layer UUID and accepts mode `replace` (default), `toggle` or `range`. Range uses the filtered panel order. `linked` optionally accepts the context layer UUID. Other operations reject irrelevant target/mode parameters. State reports the active UUID (or null), selected UUIDs in document order and availability. The API shares native selection and Actions playback, rather than a separate pixel transaction.

Invalid or irrelevant parameters return 400, missing layers 404, stale/busy requests 409, and unavailable linked selections 422. Current revisions remain opaque 64-character hexadecimal strings. Typed catalog 249; native archive 86; Actions 49. No equivalent panel-selection endpoint is defined in the pinned published Adobe v2 contract, so no compatibility route is invented.

All 127 focused Debug tests pass. They cover all ten supported component-mode/depth contexts, preserved source samples/history/Redo, recording and mixed playback, sparse 300000² selection-only recipes, native/API equivalence, stale/busy/invalid requests, filters and owned offscreen native hit/accessibility/mouse actions. Both normal optimized architectures pass 393 of the same 395affected cases, including all 66 new feature methods from checkpoints 415–425. Two existing linked-alpha/master-palette failures have the same diagnostics as checkpoint 424. The Debug-crashing clipboard method passes both normal architectures; no Debug repair is claimed. The universal package passes both macOS 14 slices, signature and ZIP checks. Physical UI/reference validation remains pending Mac unlock. Full L01, Group/Advanced Blending/library/extended-empty workflows, exact multi-selection ordering and full Photoshop acceptance remain open. [Evidence](LAYER_SELECTION_425.json).
