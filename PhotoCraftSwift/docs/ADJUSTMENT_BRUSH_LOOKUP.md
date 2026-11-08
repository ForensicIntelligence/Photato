# Color Lookup with the Adjustment Brush

Choose Color Lookup in the Adjustment Brush picker and paint. Photato creates an editable lookup adjustment with a black mask that reveals the effect where you paint. Use Properties to load a LUT or choose a Photato Look, then set interpolation and Dither. Add/Subtract, object targeting, mask properties, Preview/Cancel and Undo/Redo share the existing adjustment-mask workflow. Existing lookup layers can also be refined or retyped.

New native lookup layers start with no LUT, which is identity. The live Photoshop reference offered Color Lookup and created a masked lookup layer on the owned test photo. Its current filmstock_50.3dl setting is not established as a factory default; no Adobe lookup assets are bundled. Exact defaults, Color and vibrance semantics and complete B08 parity remain open.

## API

Existing `adjustmentBrush.stroke`, `adjustmentBrush.object` and `adjustmentBrush.edit` with `operation:replace` accept `kind:colorLookup` and these settings:

| Setting | Meaning |
|---|---|
| `lutID` | Table from the existing session LUT upload route |
| `preset` | A named Photato Look; mutually exclusive with lutID |
| `interpolation` | trilinear or tetrahedral |
| `dither` | Boolean |
| `clearLUT` | True removes the embedded table; cannot accompany a reference |

Omitted table fields preserve an existing layer’s embedded table. An omitted interpolation or dither value also retains the existing value. New layers use the existing trilinear/true defaults. State `settings` contains editable scalars; `lookup` reports read-only LUT metadata. The existing per-layer LUT download retrieves original bytes. Uploaded LUT permissions/cache limits and native/API sharing/request limits remain separate. Clearing the session cache does not change layers or prevent later mask refinement using their embedded data.

Unknown or conflicting settings reject400, absent session tables404, stale/busy/cancelled/revoked requests409. Existing invalid document/mask/lock and preparation errors remain atomic. No raw table, filesystem path or URL is accepted through these settings. Native and HTTP paths use the same Swift commands and rendering.

## Files, Actions and checks

Lookup layer storage retains native 18 compatibility; latest native 90 and266 typed commands are unchanged. Portable recorded Color Lookup brush strokes or object operations require Actions 59, with original table data embedded for replay. Earlier brush and action feature minima remain. The API’s existing transport limits for action files are separate from the native 16 MiB library limit.

All 94 selected Debug methods and the same94 optimized methods on Apple Silicon and translated Intel pass, including 8 new methods. Checks cover local painting across RGB depths, untouched samples, selection/masks, preview/Cancel, history/files, native Properties/retyping/object targets, embedded replay/version gates, HTTP references/presets/scalar/reset behavior, invalid/stale/busy/revoked work, and existing lookup/PSD/Adobe/menu/cursor/RGB32 regressions. These are selected implementation checks, not a full suite or complete Photoshop output proof.

Photoshop detection/defaults/interpolation/dither/profile output, ICC/CSP import, larger object masks, full presets/Tool Presets, physical supported platforms, native live interactions and60 fps remain unqualified. Full original B08 scope and all earlier failures remain open.

[Evidence](ADJUSTMENT_BRUSH_LOOKUP_478.json) · [Developer record](DEVLOG.md#dev-step-478)
