# Cylinder Warp

Cylinder Warp curves rectangular artwork around a cylindrical surface, which is useful for packaging mockups. The Warp sheet has two corner handles for resizing, top and bottom curvature handles, and a horizontal perspective control. Hold Shift during a corner drag to keep the proportions. You can move the whole wrap by dragging the image inside its outline. The sheet also has numeric controls for curvature, perspective, and bounds. The UI uses Photato’s native Warp sheet and existing preview and Undo behavior. [Adobe’s Cylinder Warp guide](https://helpx.adobe.com/photoshop/desktop/effects-filters/artistic-stylize-filters/warp-a-layer-wth-cylindrical-transform.html)

The format stores a horizontal Cylinder as seven values in the placed layer’s `warpValues` record. Photato keeps those values as a typed program. The renderer interpolates published measurements for the visible front of the cylinder, builds the corresponding surface, and omits the hidden back. The projected placement quad uses the control hull. Smart Objects keep their source and Warp settings. When replacement artwork changes size, the editor scales the bounds and rim dimensions in source coordinates and can keep the placed size. A linked preview keeps its saved settings while the original is missing. [Public Photoshop 2026 measurements](https://github.com/storytold/photocraft/issues/4112)

Supported PSD and PSB files reopen with editable settings. Native archives containing a Cylinder use version 98. Regular raster Warp still uses version 24, and the largest streamed original without a Cylinder still uses version 97. The Photato `layer.warp` command uses the same settings and rendering path as the desktop. The Adobe-compatible manifest reports the placement quad. There is no dedicated published Adobe Photoshop API v2 Cylinder command.

```json
{
  "style": "cylinder",
  "cylinder": {
    "left": 16,
    "bottom": 236,
    "right": 304,
    "top": 12,
    "topDepth": -0.2,
    "bottomDepth": 0.45,
    "wrap": 0.375
  }
}
```

Bounds use unwarped source pixels. Curvature values are relative to the half-width. Wrap ranges from 0 to 1. The settings fit inside the request’s `settings` object. Separate classic Warp distortions, a custom mesh, and vertical orientation are invalid with Cylinder. Choose Custom in the desktop sheet to convert the editable surface to a four-patch mesh.

The installed Photoshop 2026 AppleEvent query timed out. Tests use owned artwork and the published geometry measurements. An original Photoshop Cylinder PSD and byte-identical Photoshop rerendering are still needed for independent parity verification. PDF Warp and the reconstruction of an original pre-Warp mask from a saved placed mask also remain open.

## Validation

All 134 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. The prior Intel RGB32 difference reproduced in a separate run. Both slices of the signed macOS 14+ universal preview launched offscreen.

Five new tests cover the front surface, native controls and modifiers, authenticated exports and embedded or linked Smart Objects. A sparse 300,000 × 300,000 source passed Warp and exact Undo. 3 of 3 owned 16-bit Cylinder composites and 6 of 6 Photoshop containers matched byte for byte across the three Photato configurations. The eight existing Intel RGB32 PSDs and the three published Warp regression files match checkpoint 667.

[Qualification](SOURCE_PUBLICATION_668.md)
