# Brush textures from saved patterns

Open **Window > Brush Settings**, select **Texture**, then **Choose Pattern…**. The menu follows the groups in the Patterns library. Define or import a pattern in the existing Patterns panel first. Choosing a pattern embeds its height samples in the current brush and enables Texture. Existing scale, brightness, contrast, mode, depth, dynamics and inversion settings are retained. Explicit pattern selection works independently of preset-section locks.

The generated Paper, Canvas, Noise and Dots choices remain available. Selecting one, or choosing **Use Generated Pattern**, clears the custom bitmap. The panel shows embedded dimensions. Preparing a large texture runs in a cancellable worker; the Cancel button stays available while settings controls are disabled. Cancelling or failing a load preserves the entire previous brush state.

Choosing a texture changes tool settings, without document pixels or image Undo history. A following stroke captures the samples and uses ordinary preview, Cancel, document Undo/Redo and recorded Actions. Saved native brush presets and supported ABR export also embed the samples. Later editing, removal or replacement of the source pattern does not change those captured brushes or strokes. Texture pattern names/IDs are not retained as live library dependencies.

## Optional API

Use the existing `pattern.library` interface to list, define or import patterns, then send the selected stable pattern ID through `brush.configure`:

```json
{
  "command": "brush.configure",
  "revision": "<current revision>",
  "parameters": {
    "brush": {},
    "texturePatternID": "<pattern ID>"
  }
}
```

`brush` remains required and may include a partial tool/color patch. The pattern is resolved after that patch: it supplies `settings.texture.bitmap` and enables `settings.texture.enabled`. Both the patch and texture publish together after preparation succeeds. No part is applied after cancellation, stale document/session/settings/library state or revoked sharing. The response contains the normal brush state and new revision. `state.textureLoading` reports preparation; discovery describes the source, conversion and limits. Existing clients and inline bitmap configuration are unchanged. There are still 260 typed commands, native archive maximum 88 and Actions maximum 54.

Unknown pattern IDs return 404, malformed fields 400, busy/stale/cancelled/revoked in-flight operations 409, and unsupported size or preparation failures 422. Authentication retains its existing 401 behavior. `paint.stroke` uses the configured captured brush and adds one document Undo step. There is no dedicated brush-pattern operation in the pinned Adobe Photoshop v2 contract; unsupported brush descriptors stay explicit. No Adobe route is invented.

## Processing and current limits

Patterns must fit within 2500 × 2500 pixels. Oversized library entries are disabled in the picker and rejected through the API. No resizing is performed. The helper shares the existing ABR brush-texture conversion: encoded RGB luminance `0.2126R + 0.7152G + 0.0722B`, multiplied by alpha, clamped and rounded to unsigned 8-bit samples. The existing brush texture sampling and rendering algorithms are unchanged.

This conversion is Photato's current behavior. Exact Photoshop grayscale, profile/alpha interpretation, defaults, texture positioning and pixel output remain unqualified. Full B01 scope, physical tablet/platform checks and sustained 60fps remain open. All 40 selected Debug tests pass, including ten new methods. Actual native testing confirms choosing a saved pattern, an embedded 8 × 8 texture with ready preview, painting, document Undo/Redo and normal Quit. Preset/ABR/disk/Actions persistence, cancellation and deferred API revocation are automated checks. Offscreen Light/Dark captures have incomplete controls and do not qualify appearance; the actual native dark panel was inspected. Normal optimized build454 is deferred under the breadth policy; latest optimized universal remains453. [Checkpoint evidence](BRUSH_PATTERN_TEXTURES_454.json) records sources, binaries, failures and remaining requirements.
