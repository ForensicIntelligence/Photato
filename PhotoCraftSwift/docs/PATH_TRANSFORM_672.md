# Free Transform for paths

Select a path in the Paths panel or select a vector mask or shape contour. Use Path Selection for whole contours and Direct Selection for anchors or segments. Shift-click to change which contours or anchors are selected. Press Command-T for the shared transform box with Scale, Rotate, Skew, Distort, or Perspective. The Edit menu also provides fixed rotations and flips. Return applies one edit and Escape cancels.

The transaction changes the selected path geometry. It preserves the rest of the layer, including pixels, placement, and separately attached masks. A transform of a vector mask preserves its enable, linkage, density, and feather settings. Shape contour edits use the native editable cubic representation and retain fill and stroke. Editing the contour of a live primitive can replace its parametric controls.

Affine transforms map the selected anchors and handles directly. For Perspective and Distort, segments with both anchors selected use editable cubic fits within 1/64 document pixel. At a selection boundary the unchanged side retains its anchor and handles. Geometry beyond the supported limits or across a projective horizon fails atomically.

Photato's `path.transform` command accepts an explicit saved path, vector mask, or shape target and a document-coordinate homography. Clients can send zero-based contour indices or anchor pairs and read the resulting indices if the fitter adds anchors. Native Actions version 76 records the transformation and reuses the same operation during playback. [Photato Automation API](AUTOMATION_API.md) · [Adobe Free Transform](https://helpx.adobe.com/photoshop/desktop/crop-resize-transform/resize-adjust-resolution/transform-images-shapes-and-paths.html)

Direct Selection marquee, cross-layer path selection, mesh Warp on a path, and live Photoshop checks of partial perspective behavior remain open.

## Validation

All 156 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

The path workflow passed native canvas gesture, Return, Undo, Action replay, authenticated editing, and PSD and PSB tests. All 12 whole-layer vector mask outputs from build 671 matched byte for byte. A separate Debug comparison passed all 34 existing Pen, Shape and menu cases on both builds.

[Qualification](SOURCE_PUBLICATION_672.md)
