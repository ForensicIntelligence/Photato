# Photato photographic Relight

Relight is a deterministic local photographic lighting filter, translated from PhotoCraft's MIT OR Apache-2.0 renderer into Swift. It estimates luminance shading and applies directional lighting. Its current qualification and original-engine comparisons are recorded in [the Relight evidence](RELIGHT_REFERENCES.json); all13 new functional/model/interchange cases pass at318 Source06. The wider258-case selection retains six earlier strict failed cases. Seven direct Float32 and19 uncached source vectors match the separately recorded original-engine oracles exactly. This is bounded fixture evidence, not complete Photoshop equivalence.

Choose **Filter → Photato → Relight…** with an editable RGB pixel layer or Smart Object selected. The sheet provides direction, elevation, intensity, ambient light, warmth and softness, a preview, Reset, local Undo/Redo, Cancel and OK. Preview uses a scaled image with a maximum side of192 pixels. OK uses the full-resolution shared command and one document history transaction. Cancel leaves the document unchanged. Editing an existing Smart Filter also exposes its opacity and blend mode. Photoshop's captured factory shortcuts remain the reference; this Photato extension has no default shortcut.

| Control | Range | Default |
|---|---|---|
| Direction | −180 to180 degrees | 45 |
| Elevation | 0 to90 degrees | 40 |
| Intensity | 0 to100 percent | 40 |
| Ambient | 0 to100 percent | 55 |
| Warmth | −100 to100 | 0 |
| Softness | 1 to100 percent | 25 |

The optional Photato API exposes the same engine through `filter.apply` and `smartFilter.set`. Use the current shared-document revision and layer identity in the existing authenticated command route:

```json
{
  "command": "filter.apply",
  "revision": "<current document revision>",
  "parameters": {
    "layerID": "<layer UUID>",
    "filter": {
      "kind": "relight",
      "relight": {
        "angle": 45,
        "elevation": 40,
        "intensity": 40,
        "ambient": 55,
        "warmth": 0,
        "softness": 25
      }
    }
  }
}
```

Omitted controls take the defaults above. Unknown fields, booleans used as numbers, nonfinite values and out-of-range controls reject. Busy or stale revisions retain the usual409 behavior; invalid parameter JSON returns400, and unsupported document/rendering context returns422. Capability discovery includes the Relight settings schema, processing limits and workspace state. Native editing and API commands share document validation, pixel processing and history.

Editable Relight Smart Filters require **native archive71** and recorded filter/stack operations require **Actions26**. Native downloads must explicitly admit archive71 with `X-Photato-Archive-Version: 71`; an older requested version rejects a document containing the feature. Original PhotoCraft `filter.render.relight` programs migrate to these typed controls while retaining original source bytes and saved appearance. Read [the source migration evidence](SOURCE_FILTER_IMPORT_REFERENCES.json) for its independently inventoried command coverage.

Current processing supports RGB8/16/32 with alpha and HDR handling, up to8,388,608 source pixels per operation,128-pixel scratch tiles and a bounded Gaussian halo. Document-size support is broader than this filter's processing qualification. Full capacity, physical60fps, complete platform and exact original/Photoshop output acceptance remain open. Saved original appearance and newly rendered output are measured separately.

This filter is a Photato extension. Adobe Harmonize/Firefly generative lighting matching, multi-light Lighting Effects and generative AI are separate workflows. Adobe action descriptors for this extension and editable PSD/PSB storage reject explicitly; native storage retains the settings. Existing Adobe-compatible resource jobs keep their published input-format boundary. The Photato interface can render imported PhotoCraft documents through its own resource jobs.
