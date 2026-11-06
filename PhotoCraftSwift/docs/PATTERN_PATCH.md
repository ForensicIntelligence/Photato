# Pattern Patch

Select an area on an unlocked ordinary RGB raster layer, choose **Patch > Normal** in Options, choose a saved pattern and click **Use Pattern**. The picker includes document patterns before the native library. A document resource wins when IDs overlap. The selected pattern is captured when preparation starts; later picker/library changes do not alter that work.

This uses the pattern as a donor for the existing Normal healing/diffusion solver, rather than plain Pattern Fill. Diffusion and Transparent retain the Normal Patch controls. Sampling uses the existing wrapping sampler at100% and document origin; exact Photoshop phase/alpha/solver behavior is unqualified. Source/Destination drag offsets are not used by the pattern operation. Cancel or Escape during preparation leaves the document unchanged. A successful edit creates one Undo; a no-op does not dirty. Selection representation, outside pixels, masks/transforms/metadata and protected alpha are retained.

The selected solve window, including a two-pixel border, and its transformed output each currently support at most4,194,304pixels. Work is bounded to that region, so a small repair can run on a300,000×300,000sparse canvas. This does not establish dense maximum performance or remove other Patch/Move/RedEye limits. Pattern assets retain their16MPlimit. Smart Objects, projected storage, other color modes and mask/channel targets remain unsupported here. Full B05 remains open.

The optional Photato API extends existing `retouch.patch` without adding a command:

```json
{
  "command": "retouch.patch",
  "revision": "<current document revision>",
  "parameters": {
    "layerID": "<raster layer UUID>",
    "patternID": "<saved document or native-library pattern ID>",
    "diffusion": 5,
    "transparent": false
  }
}
```

Use patternID instead of dx/dy. Only layerID, patternID, diffusion and transparent are accepted in this branch; drag/mode/type/Content-Aware settings cannot be mixed into it. The original dx/dy drag contract remains supported. Missing patterns, invalid combinations, busy work, stale revisions and revoked requests commit nothing. `regionRetouch` state includes selected/captured pattern IDs and saved pattern metadata. Capabilities expose the separate Pattern Patch canvas/solve/output limits. Native and API use the same preparation and history path. Typed250/native archive86/Actions49/settings4/menu/shortcut inventories are unchanged. No Adobe endpoint or unqualified actionJSON descriptor is invented; portable semantic retouch Actions remain open.

Checkpoint432 passes40focused Debug cases, including nine new methods, and the same199selected optimized cases on ARM64 and Intel under Rosetta. All55new426–432methods pass per architecture, including17since430. Analytical single-unknown texture/diffusion values and exact old-Normal-donor comparisons cover three depths×three diffusion settings. Maximum sparse canvas, soft selection, alpha, transforms, native/API/Undo/archive and cancellation/stale/revocation paths pass. The current LUT files from both normal architectures match the431files independently checked by OCIO/LittleCMS/ColorSync. Universal macOS14slices/signature/ZIP checks pass. These are selected tests, not a full-suite, physical-platform or Photoshop equivalence result. The Mac remains locked. The owned offscreen control capture does not qualify live button appearance.

Three failed Debug attempts and the packaging-helper preflight failure are retained before repair. Repairs after the initial app build changed only new tests/helpers; all four Debug production app hashes are identical. No old fixture or tolerance was weakened. [Evidence](PATTERN_PATCH_432.json).
