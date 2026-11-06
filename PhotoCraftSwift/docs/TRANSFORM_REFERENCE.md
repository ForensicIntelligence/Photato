# Transform reference point

Enable **Show Reference Point** in the transform Options bar, then drag the point inside or outside the bounds. The nine-position locator chooses a preset and clears a custom point. Rotation, numeric scaling and Option scaling use the chosen point. X and Y identify that point. Moving it alone leaves the image and Undo history unchanged. Existing transform Apply/Cancel and matrix samplers remain in use.

This applies to the existing Free Transform, Transform Selection, selected-pixel, pixel-mask, saved-channel, layer-collection and Content-Aware Scale drafts. Warp and filter workspaces retain their own controls. Visibility belongs to the open workspace/session and is copied into a newly opened workspace; complete Photoshop preference persistence is not claimed.

The pivot uses the scope cursor for all 16 Control/Command/Option/Shift combinations. Space before press keeps Hand. A captured drag retains its cursor; Escape or focus/tool/detach changes cancel that interaction. Session/owner/source guards prevent a cancelled interaction restoring over later work.

The optional Photato API exposes `transformReference` state and the `transform.reference` command. Fetch the current document revision and `transformReference.workspaceRevision`, then send the operation using the existing command envelope:

```json
{
  "command": "transform.reference",
  "revision": "<document revision>",
  "parameters": {
    "workspaceRevision": "<current workspace UUID>",
    "point": {"x": -20, "y": 40},
    "visible": true
  }
}
```

Use `anchor` instead of `point` to select one of the nine advertised presets. At least one of `point`, `anchor` or `visible` is required; point and anchor are mutually exclusive. Point coordinates are finite document coordinates within ±1,000,000. Reference-only changes update the workspace revision without changing document bytes/revision, previews, Undo or recorded Actions. Active pointer, unavailable/busy workspace, stale revisions and revoked shares commit nothing. The active-transform preflight exception is restricted to this command; ordinary editing commands remain blocked during a native transform.

There is no corresponding native workspace endpoint in the pinned Adobe Photoshop v2 contract. Existing Adobe matrix operations retain their contracts. Typed commands now total 250; native archive 86, Actions 49 and settings 4 are unchanged. No menu identity or shortcut is added.

Checkpoint 429 passes all 130 focused Debug tests, including seven new methods: analytical affine/projective pivot math, six target contexts without preview/document changes, every-depth native matrix commits and Undo, all 16 modifier drags, cancellation/stale state, API validation and Content-Aware Scale preview readiness. The owned offscreen locator capture was visually checked. Source01's compile failure and Source02's two stale catalogue counts were preserved before repair. No old pixel expectation, fixture or tolerance was changed.

Transform Again, remaining G01 functionality, exact Photoshop defaults/output/modifiers/persistence and broad platform/performance qualification remain open. The current build has not received optimized universal or full-suite qualification; checkpoint 428 remains the last such focused batch. [Evidence](TRANSFORM_REFERENCE_429.json).
