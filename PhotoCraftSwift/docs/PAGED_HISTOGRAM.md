# Paged Curves and Levels histograms

Checkpoint440 adds exact-count analysis for ordinary pixel layers without visiting every implicit raster cell. Native Curves and Levels use the shared analysis request. The optional Photato API exposes the same request as `tone.histogram`.

Each allocated image/mask union tile is examined once. Unallocated cells contribute their exact multiplicity to UInt64 counters. Edge-tile padding is excluded. A positive selection value includes a cell once, including feathered coverage; positive image alpha also counts once. These are the existing statistics rules, not alpha-weighted measurements. The existing encoded 8/16 and linear 32 sample conversion and 8-bit luminance rounding are retained.

Whole-cell translated rasters are intersected with canvas and selection before analysis. Image and world-space coverage are cropped to matching local grids with the existing raw/paged crop implementation. Fractional/rotated affine layers retain the original per-cell path. Adjustment layers analyze their composed input before their own parameters, mask and opacity; this change does not remove the compositor's existing capacity limits.

## API

POST to the existing authenticated `/v1/documents/<shareID>/commands` route:

```json
{
  "command": "tone.histogram",
  "revision": "<current revision>",
  "parameters": {
    "layerID": "<pixel or adjustment layer UUID>",
    "luminance": false
  }
}
```

Pixel layers use the document selection by default. Set `useSelection:false` to read their unselected canvas intersection. Omit `useSelection` for adjustment input, matching the native inspector. Unsupported layer types reject with 422; malformed parameters reject with 400, missing/revoked sources with 404, active native edits or stale revisions with 409, and another concurrent preview/statistics operation with 429. A source or sharing change while awaiting analysis discards the result. Read-only analysis does not create Undo steps, modify pixels or advance the document revision.

The response includes `histogram`, `revision`, `sourceDepth`, `layerID` and `luminance`. Histogram data has three 256-bin `channels`, plus `samples`, `transparent`, `invalid` and three-element `underflow`, `overflow`, `shadows`, `highlights` counters. `/v1/capabilities` includes parameter/result schemas and the actual capacity limits. Counts fit UInt64 at the 90-gigapixel logical limit; pooled RGB counts can reach 270 billion.

This is a Photato query, not a new Adobe endpoint. Existing Adobe-compatible operations and schemas are unchanged.

## Qualification and remaining work

The first qualified development run passes27focused Debug methods, including eight new methods. The same 61 optimized methods pass on Apple Silicon and under Rosetta, including all eight new methods. Universal macOS 14 packaging, signature and extracted ZIP verification pass. Earlier full-suite and strict text-output failures are not repaired by this increment. [Evidence](PAGED_HISTOGRAM_440.json). Tests compare every counter against the retained original per-cell implementation at all depths, with linear storage, luminance, masks, translations and affine fallback. Analytical maximum-size cases cover implicit counts, sparse edge pixels, translated coverage, archive round trips and bounded storage. Native cancellation/supersession and HTTP schema/history/guard tests are included. No Adobe artwork or algorithm implementation was copied.

This is an A01 analysis dependency. Curves Auto, complete Auto Color Correction Options/defaults, black/gray/white point sampling, freehand/targeted editing, mask/HDR workflows and original acceptance remain open. Existing Levels Auto Color remains an unqualified approximation. Dense maximum-size performance, arbitrary-transform large statistics, rich adjustment composition, ICC/Photoshop output fidelity, physical Intel/macOS 14 and interactive 60 fps are unqualified. Historical test failures remain recorded separately.
