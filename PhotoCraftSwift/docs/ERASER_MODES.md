# Eraser mode implementation

Photoshop's ordinary Eraser offers Brush, Pencil and Block. Build456 adds a native mode selector and shared API resolution. All44focused Debug and the same44optimized methods per architecture pass; the six captured RGB8 Block outputs are byte-identical to their owned Photoshop references. Full Eraser parity remains open. The prior software454 had only the brush eraser path. The independent reference in [checkpoint 455](ERASER_MODES_455.json) confirms that Block disables diameter, Opacity and Flow controls. The456normal-interface Pencil probe confirms available Opacity and disabled Flow; Pencil pixel/default equivalence remains unqualified.

## Captured Block results

All files use the same owned 96 × 72 RGB8 image, initially gray128, on Photoshop's Background layer with a white background color. Each row is a separate normal-interface Save As, decoded with an independent public-format PSD merged-plane parser.

| Zoom | Changed pixels | Bounding rectangle, exclusive right/bottom |
|---|---:|---|
| 100% | 256 | 40,28 to56,44 — 16 × 16 |
| 200% | 64 | 44,32 to52,40 — 8 × 8 |
| 125% | 144 | 42,30 to54,42 — 12 × 12 |
| 1600% | 1 | 48,36 to49,37 |
| 6400%, first click | 0 | None |
| 6400%, second tested position | 0 | None |

Changed pixels are exactly RGB255. The selected sizes agree with truncating 16 divided by zoom, including zero at high magnification. That is an inference, not a complete Photoshop algorithm. Other positions, continuous strokes, selections, transforms, depths and profiles still need qualification. Do not silently force a minimum footprint of one image pixel.

## Reference checkpoint455 integration plan (historical)

1. Qualify Pencil controls/defaults, then add a typed Brush/Pencil/Block setting. Retain existing brush eraser behavior and its incremental, paged and component-target paths.
2. Resolve the effective brush or dedicated block operation once at gesture start. Block ignores diameter/opacity/flow and unrelated tip dynamics; use the owned references to reject rounded or bilinearly softened squares. Preserve empty high-zoom edits without adding Undo.
3. Expose matching options and execution through existing paint.configure/paint.tool while preserving brush.configure/paint.stroke clients. Test desktop/API equality, invalid/busy/stale/revoked requests, masks/components, snapshots and subsequent Undo/Redo. Do not invent an Adobe route.
4. Keep captured settings portable in Actions. If a new semantic tool recipe needs a format revision, add the minimum-version guard and retain older brush recipes. Do not change old pixel fixtures or numeric tolerances.
5. Make cursor feedback follow the captured mode and all16modifier combinations, including pan/focus restoration. Match toolbar availability to the selected operation.
6. Run focused module/native checks, and batch normal universal qualification according to the breadth policy. Full B02 closure still needs every original acceptance criterion. Erase to History and its Option alternate need a real history source; keep that requirement in full scope (the B06 assignment in the original notes was wrong; see the correction below) and do not advertise an unavailable action.

The current Photoshop Eraser Brush also displayed 5000px. Photato's 2048px brush limit is a separate B01 capacity gap; the observation is not proof of Photoshop's absolute maximum.

No Eraser mode implementation or new app build is claimed by checkpoint455. At that reference checkpoint software was454 and optimized universal453; implementation and optimized universal456 now supersede those versions.

## Development build 456

The Eraser toolbar has Brush, Pencil and Block modes. Brush retains the existing stroke behavior. Pencil uses the current hard, aliased Pencil flags, retaining opacity and supported dynamics. Block resolves a solid square at the captured zoom, ignores diameter/opacity/flow and unrelated tip dynamics, and retains the current smoothing settings. Its selected high-zoom zero footprint produces no stroke. Source brush settings are unchanged when modes change. Exact Pencil defaults and wider Block paths remain open.

Mode and effective brush are captured at gesture start. Existing stroke, mask and channel commands remain authoritative, including their incremental/paged/component behavior and document Undo. Recorded Actions carry the resolved brush samples, diameter and settings; no new semantic recipe or format is required. Native archive88, Actions maximum54 and260typed commands remain unchanged.

Erase to History is disabled until a real history source exists. Option-start on Eraser is unavailable and does not erase; its cursor reports unavailable. Other modifiers and temporary Hand/focus restoration keep their existing policies. This does not implement Photoshop's history restoration.

### API

`brush.configure` retains its required partial `brush` object and adds optional `eraserMode` with `brush`, `pencil` or `block`. It updates the native Eraser mode without document pixels/history or replacing stored brush settings. When combined with texture pattern preparation, the mode publishes only after the complete operation succeeds. `brush.eraserMode` exposes the current choice.

`paint.stroke` adds optional explicit `eraserMode` and `zoom`. Supplying a mode requests erasure through the same resolver as the desktop. Zoom is the captured view scale (1 means100%) and defaults to the brush's existing zoom. It must be between0.01 and64. Supplying zoom without an eraserMode is rejected. Existing target/layer/channel, authentication, sharing/revision, busy, Undo and Action contracts remain.

```json
{
  "command": "paint.stroke",
  "revision": "<current revision>",
  "parameters": {
    "eraserMode": "block",
    "zoom": 1.25,
    "points": [{"x": 48, "y": 36}]
  }
}
```

Omitting eraserMode preserves the legacy brush and brush.erase contract, even if a different native Eraser mode is configured. Clients opting into the new modes pass that choice explicitly. `brush.settings.mode` is still the brush blend mode, separate from eraserMode. No Adobe endpoint or unsupported history descriptor is invented.

The implementation uses existing brush limits (including2048px diameter and current zoom/stroke budgets); the observed Photoshop5000px state remains a B01 requirement. [Build456 evidence](ERASER_MODES_456.json) records the44Debug/same44optimized cases per architecture, alltennew methods, six exact owned Block references, and native results. The optimized application opens the ownedPSD, performs Blockerase/UndoRedo, closes the restoredimage and quits normally. Its universal macOS14 metadata, production sandbox entitlements, signature and extractedZIP verify. The earlier Debug session had disabled Open/Quit despite a clean document; it required explicit force-quit cleanup. That failure is unresolved and is not called a successful native Quit.

Correction: real history-source selection belongs to D03, History/Art History Brush to B03, and Eraser integration to B02. B06 is Content-Aware Fill and Scale. Wider positions/strokes/depths/profiles/transforms, Pencil output/defaults, physical input/60fps/supported-OS qualification and full original scopes remain open. No source upload, installation or release occurred.
