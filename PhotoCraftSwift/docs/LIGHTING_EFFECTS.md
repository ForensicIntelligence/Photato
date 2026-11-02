# Lighting Effects

**Qualification321:** All14 new functional/model/native/API cases pass on Source01; Source02 changes only two test contracts, with all30 affected checks passing and identical production/binary.22 direct/64 cached original vectors are exact;62/64 uncached vectors match, retaining two translated transparent-boundary differences. Complete3,153-case Source01 inventory has11 failed cases, including two subsequently repaired stale tests; nine strict cases remain open. This is a bounded native/source subset, not complete Photoshop or current full-green qualification.

The native Swift Lighting Effects workflow uses the licensed PhotoCraft multi-light renderer. Its current build, test evidence and remaining qualification are recorded in [the evidence manifest](LIGHTING_EFFECTS_REFERENCES.json). It is being qualified at checkpoint319.

Open **Filter → Photato → Lighting Effects…** for an editable RGB layer or Smart Object. Select a light in the list or preview, then change its type, color and intensity. Add Point, Spot or Infinite lights, duplicate/delete them, or toggle their contribution. Surface controls set gloss, metallic reflection, exposure, ambience and bump texture. This Photato submenu entry preserves the independently captured factory menu and its shortcuts; no default shortcut is assigned.

Point lights have position, height and reach. Spot lights add a target, cone half-angle and hotspot. Infinite lights use direction and elevation. Intensity ranges from−100 to100; negative lights darken the surface. The renderer accepts up to64 lights. UI fields retain finite source-list positions, heights and reaches even when they exceed the usual slider span.

Drag a preview handle to position a light or spot target. Drag an Infinite handle to change direction. Hold **Option at gesture start** to duplicate the light; hold **Shift** to constrain position/target motion to one axis or snap direction to15-degree steps. The action and cursor retain that captured mode until release. Control and Command have no invented alternate action. At the light limit, Option duplication is unavailable. The preview is clipped to its own bounds and uses at most192 pixels per side; full-resolution processing happens on OK.

Use the Presets menu for Default Spot, Point, Infinite and Three Lights styles, or Load/Save a custom JSON preset. The file contains the same strict settings object accepted by the optional Photato API. It is limited to256KiB and is not an Adobe binary preset format. Reset and local Undo/Redo change the draft; Cancel preserves the document. OK makes one shared document/history transaction. Editing a Smart Filter also exposes its opacity and blend mode.

Textures include Red, Green, Blue, layer Alpha and Luminance, with texture height and White Is High controls. A saved document alpha channel is an additional Photato texture source. `textureChannelID` identifies that document's channel; missing references reject atomically. Save/Open and channel rename retain the identity, and deleting a referenced channel is guarded. Preset/Action portability across unrelated documents with different channel identities remains unqualified; select a compatible channel before applying such settings.

The API uses the existing authenticated `filter.apply` and `smartFilter.set` commands, revisions, errors and history. Example filter payload:

```json
{
  "kind": "lightingEffects",
  "lighting": {
    "lights": [
      {"kind": "spot", "x": 0.25, "y": 0.2, "z": 0.6,
       "targetX": 0.5, "targetY": 0.55, "color": [1, 0.8, 0.6],
       "intensity": 75, "cone": 45, "hotspot": 50},
      {"kind": "infinite", "angle": -45, "elevation": 45,
       "color": [0.3, 0.6, 1], "intensity": 20}
    ],
    "gloss": 0, "metallic": 0, "exposure": 0, "ambience": 8,
    "texture": "luminance", "height": 50, "whiteIsHigh": true
  }
}
```

Light colors are three linear RGB components in0…1. Omitted fields use the documented typed defaults; unsupported fields, enums, booleans used as numbers and nonfinite/out-of-range controls reject. Capability discovery exposes settings/preset schemas, built-in styles, processing limits, pointer semantics and draft workspace state. UI and API operations share the Swift engine and transactional document state.

Editable settings require **native archive72** and filter/stack Actions require **Actions27**. Native downloads of a document using the feature must explicitly admit archive72. Older versions reject instead of dropping settings. Earlier Relight remains native71/Actions26. Original PhotoCraft `filter.render.lightingEffects` root and light-list programs map to typed settings while preserving original source bytes/programs/cached appearance. Unknown or unsupported source context rejects the entire import.

Global Colorize and the complete historical Photoshop style library/preset interchange remain unfinished. The four local presets and JSON format above are the implemented subset.

Current processing supports RGB8/16 and linear RGB32/HDR, with an8,388,608-source-pixel operation budget. This is separate from the larger document-size support. Original-engine fixtures cover bounded cases; complete source/Photoshop numerical, native visual, universal/Intel/macOS14+ runtime, large-capacity and physical60fps acceptance remain open. Adobe's current filter reference excludes16/32-bit Lighting Effects; Photato's high-depth implementation is an extension, not evidence of Adobe behavior. Published Adobe action descriptors and editable PSD/PSB settings remain unqualified and reject explicitly. Existing Photato resource jobs can render imported source projects; Adobe-compatible jobs preserve their published input-format boundary.

References: [current Adobe filter table](https://helpx.adobe.com/photoshop/desktop/effects-filters/blur-sharpen-filters/filter-effects-reference.html), [historical official Adobe control/workspace manual](https://helpx.adobe.com/pdf/cs6/photoshop_reference.pdf), the attributed original source and owned fixtures in the evidence manifest. Historical controls do not establish current Photoshop2026 menu availability or pixel equivalence.
