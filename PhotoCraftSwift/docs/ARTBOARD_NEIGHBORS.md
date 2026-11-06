# Adjacent artboards

With the Artboard tool active and a board selected, use a + control above, below or beside it to add an empty board. Hold Option when pressing the control to copy the board and its contents instead. Release over the same control to commit. Escape, releasing elsewhere, changing tools/the selected artboard/document, losing focus or using temporary Hand cancels the press. One completed edit adds one Undo step.

The new board uses the source dimensions and background. Empty boards start without contents or local guides; duplicates retain the existing duplication engine's content, background and guide handling. Placement uses logical coordinates, including negative coordinates. The existing engine grows/rebases the sparse canvas without resampling source pixels. Requests exceeding the300,000-pixel canvas extent fail atomically. Current native spacing is100 logical pixels; Photoshop's exact factory spacing/defaults have not been verified.

The existing toolbar Duplicate control, artboard menu commands and factory shortcuts are retained. There is no new shortcut or menu command. Shared native archive86 and Actions49 are unchanged; full portable artboard Action recording remains outstanding.

## API

Use the existing opt-in authenticated document command endpoint with its current revision:

```json
{"command":"artboard.edit","revision":"<current revision>","parameters":{"operation":"adjacent","layerID":"<artboard UUID>","side":"right","duplicate":true,"spacing":100,"name":"Layout variation"}}
```

`side` is top/right/bottom/left. `duplicate` defaults to false. `spacing` is an integer 0–32,768, default100. `name` is optional. Other operation-specific fields are rejected. The same request and prepared native transaction handle logical placement, locking, canvas admission, history and source validation. Busy, stale and revoked-share guards retain their existing behavior. Existing explicit artboard bounds now accept1–300000 per side, with the engine's union/residency limits still enforced.

Adobe's published create-artboard job route remains supported by its existing bounded contract; it has no adjacent-control or pointer-presentation endpoint. No Adobe route was invented for this native interaction. Pointer metadata identifies the add/Option-copy behavior, including captured press and cancellation.

## Validation and remaining work

Checkpoint427Source04 passes41 focused Debug cases including8new methods,24 side/depth/create-copy combinations and16 modifier combinations. Tests check source content retention, exact native/API rendered results, archive bytes/round trips, Undo/Redo, cancellation and invalid/busy/stale/unshared requests. The owned offscreen capture checks layout only.

The broader Source02 run crashed in an existing Frame draw-over-image test. That case also crashes in the retained 426 Debug binary. It is explicitly excluded from the narrower41-case pass and remains open; no cause, crash repair, full-suite or normal427pass is claimed. Current optimized/universal/physical qualification remains batched. Exact Photoshop factory behavior and output parity, nesting/dissolve and the remaining L07 scope are still outstanding. See [evidence](ARTBOARD_NEIGHBORS_427.json) and [development log](DEVLOG.md#dev-step-427).
