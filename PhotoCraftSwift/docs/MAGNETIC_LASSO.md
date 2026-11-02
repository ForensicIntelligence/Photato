# Magnetic Lasso

The existing Magnetic Lasso entry in the L tool group now opens a native tool. L and Shift-L use the existing factory-group routing. Options include selection mode, Feather, Anti-alias, Width, Contrast, Frequency and Tablet Pressure. Photoshop 2026 is the target. The independently authored gradient tracer has not been qualified against Photoshop's exact edge paths, masks or defaults. Adobe's current guide excludes32-bit images; this workflow currently supports RGB8/RGB16.

Click to begin, move or drag along an edge, and click to fasten a point manually. Delete removes to the preceding fastening point. Return, double-click, Command-click or clicking near the first point closes the path. Esc or Command-period cancels. Option-click makes a straight segment; Option-drag draws freehand. Initial Shift/Option selection modifiers are captured separately and must be released before Option becomes a temporary tracing mode. [ and ] change width by one pixel during the trace. Caps Lock enables a width indicator before tracing. Space permits temporary panning.

Selection mode and non-width settings are captured at start. Their controls disable during the trace; bracket width changes become ordered replay events. Preview classification runs incrementally off the main actor; the canvas draws the latest pointer feedback immediately, then accepts the processed trace. Every input event is retained subject to bounds. Cancel, tool change, document read/close and window resignation discard uncommitted tracing. Finishing waits for queued work, prepares the mask off the main actor and rejects a stale source. One native Magnetic Lasso Undo transaction preserves source pixels/profile/depth. Actions records explicit final coverage using the existing format.

## Native model

The source is the visible RGB composite converted to an SDR sRGB guide. The tracer samples RGB gradient ridges normal to pointer movement, favors edges near the pointer, applies a contrast threshold, narrows search width with tablet pressure and inserts distance-based fastening points according to Frequency. Manual/freehand/straight points retain explicit positions. Final polygon rasterization and Feather use the shared native selection engine. These formulas are documented Photato behavior, not a claim to Adobe's proprietary algorithm.

Sources and selections retain tiled storage. There is no new36MP or side-dimension admission cap. The sparse300000×300000 test uses a small selection on an implicit canvas; it does not demonstrate dense maximum-capacity editing. Interactive physical60fps, real tablet behavior and supported-platform qualification remain open.

## APIs

`selection.magnetic.configure` changes tool settings without document/history edits. `selection.magneticLasso` replays ordered events through the same engine and commits one selection transaction. The catalogue now has221 commands. `magneticLasso` state and capabilities expose availability, settings, active/loading/preview/finishing state, event/fastening counts, errors and parameter/result schemas.

Events are move, anchor, freehand, straight, remove or width. Point events use point{x,y} in document pixels, with optional pressure0–1 (default0 for mouse). Remove carries no point/width; width carries only its width1–256. Supply selection mode replace/add/subtract/intersect and optional straightClose. Native100000 events/250000 generated points and API8192 events/4MiB requests apply; existing shared-document limits are unchanged. Invalid, busy, stale and revoked work preserves source/history. API cancellation uses existing prepared-operation cancellation.

```json
{"command":"selection.magneticLasso","revision":"<current revision>","parameters":{"settings":{"width":10,"contrast":10,"frequency":57},"events":[{"kind":"anchor","point":{"x":4,"y":4}},{"kind":"move","point":{"x":20,"y":4}},{"kind":"move","point":{"x":20,"y":18}},{"kind":"anchor","point":{"x":4,"y":18}}],"mode":"replace","straightClose":false}}
```

Adobe's published v2 API has no dedicated Magnetic Lasso route. Unverified semantic actionJSON remains unsupported; native coverage Actions is a separate interface. No Adobe route or proprietary algorithm equivalence is invented.

## Validation

All 14 new and 235 affected optimized cases pass, with zero failures, unexpected errors or crashes. A separate checker verifies all 768 analytical mask bytes. Sparse 300000×300000 output is tested; physical maximum dense capacity,60fps, the complete current suite and exact Photoshop paths/pixels/defaults/UI/platform behavior remain unqualified.

Cases cover width/pressure/contrast/color gradients/frequency, manual/freehand/straight/deletion, width changes, mask/feather, all history/Actions modes, sparse dimensions, invalid input/cancellation, real offscreen canvas and tool cycling, native lifecycle/stale guards, profiles/depth/locks/32-bit admission, actual HTTP equality/configuration/Undo/schema/errors/revocation, all16 modifier combinations/captured mode, brackets/Delete/Esc and precision. Owned analytical mask output is checked separately without the Swift decoder. No live Photoshop/native comparison is claimed: fresh344 app access reports the Mac locked. All 104 scopes remain open. Native82/Actions30, installed283/private full298/store332 are preserved.

[Evidence](MAGNETIC_LASSO_REFERENCES.json) · [Adobe Magnetic Lasso guide](https://helpx.adobe.com/photoshop/desktop/make-selections/freehand-selections/snap-to-image-edges-using-magnetic-lasso-tool.html)
