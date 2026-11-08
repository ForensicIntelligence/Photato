# Sampled Hue/Saturation colors

Checkpoint 485 fixes import of the four captured Photoshop Hue/Saturation files containing sampled swatches. The sample's hue, saturation and lightness are retained through AHU presets, PSD/PSB and native documents. Properties uses those values for the original swatch and exposes them as an accessibility value. The existing pixel-transfer equations are unchanged.

The source passes all 68 selected Debug checks and the same 68 optimized checks on Apple Silicon and translated Intel, including 14 new tests. Native import, orange/gray swatches, range editing, retained saturation/lightness, one History Undo, canvas-focused Undo/Redo and owned cleanup pass in the isolated universal candidate. Full A02 remains open.

## Settings

Each of the six color ranges has these fields:

| Field | Meaning |
| --- | --- |
| `values` | Hue, saturation and lightness adjustments applied to pixels. |
| `bounds` | Four ordered, unwrapped degree values defining the range and its falloff. |
| `displayColor` | Optional sampled swatch, expressed as integer `hue`, `saturation` and `lightness`. |

`displayColor.hue` accepts 0 through 360; saturation and lightness accept 0 through 100. Missing or null display color uses the existing factory-style swatch: the range's inner midpoint, saturation 100 and lightness 50. An explicit retained color is validated and serialized separately from the adjustment values. Native range-bound edits update its hue and preserve its sampled saturation/lightness.

Ordinary 100-byte AHU settings remain supported. A represented sampled swatch requires the 136-byte form. PSD/PSB writes retain all six swatch triples, including unchanged factory colors. Invalid color values reject rather than being clamped or discarded. Saving an unchanged preset with its original record preserves the original bytes.

## Optional API

The existing `adjustmentBrush.edit` operation supports the new field when replacing settings on a masked Hue/Saturation adjustment layer. Use `operation: "replace"`, its `layerID` and `kind: "hueSaturation"`. The settings and state schemas include `ranges[].displayColor`.

For example, modify a complete settings object returned by the existing adjustment-brush state:

```js
settings.ranges[0].displayColor = {
  hue: 37,
  saturation: 65,
  lightness: 50
};
```

Supply that object as `settings`. Ordinary partial top-level edits retain unspecified settings. Replacing `ranges` follows the existing complete-array contract: provide six range objects with their `values` and `bounds`. Set a range's `displayColor` to null to remove its sampled override. Unknown properties, nonintegers and out-of-range values reject with HTTP 400 before publication. Stale revisions reject with 409. Shared preparation, document permission, busy checks and Undo remain in force.

Native file downloads containing this metadata require file-transfer permission and `X-Photato-Archive-Version: 92`. Default permission denial is 403; missing or older version negotiation is 422; a valid permitted download is 200. Native 91 selected-gray documents and native 90 sparse-video documents retain their existing minimums and can also use the newer version. Only documents with retained display colors require 92.

Portable Actions containing these colors require version 60. Earlier recipes retain their prior minimum versions. A file declaring an older version for sampled settings is rejected. The typed document-command count remains 266. No new HTTP route or Photoshop/Firefly descriptor is introduced.

## Reference and remaining work

Four owned Photoshop 2026 files record plain orange sampling, adding green, subtracting orange and plain gray sampling. Their file hashes, RGB source bands, range bounds and swatch triples are in `Tests/PhotoCraftImagingTests/Fixtures/sampled-hue-ranges485/provenance.json`. The initial native regression tests reproduce the importer rejection. A public-format reader checks the exported `hue2` records independently of the native decoder: 16 fresh/retained PSD/PSB exports and 2,176 record bytes per variant, 6,528 bytes across Debug, optimized Apple Silicon and translated Intel.

These files use neutral adjustment values. They establish settings-record fidelity for the captured cases. Full image-transfer fidelity, edited-sample rounding, all depths/profiles, prominent-color analysis, on-canvas sampling, targeted dragging, supported physical platforms, accessibility and 60 fps remain open. Existing Hue/Saturation range/overlap and Color Balance numerical gaps are retained in the A02 plan. Earlier failures and the separate checkpoint 484 Fill modal remain unresolved.

Photoshop plug-in hosting remains a separate open feature under AUT03. The optional HTTP API does not supply UXP, CEP, ExtendScript or native C++ plug-in hosting.

[Checkpoint evidence](SAMPLED_HUE_RANGES_485.json).
