# Transform geometry for linked Smart Objects

## 20 November 2026

A linked PSD or PSB can open with a raster preview in document coordinates even when its original artwork is unavailable. That preview has its own rectangle. The Smart Object descriptor separately retains the transform of the original artwork. Reading the preview's transform directly caused Properties to report zero rotation for already rotated artwork. A further transform could also leave the X, Y, W and H controls using an oversized preview rectangle.

Adobe documents precise positioning, sizing and rotation through Free Transform. The installed Photoshop 2026 session timed out on a read-only version and document-count query. Exact Adobe readouts, rounding, and the placement of its on-canvas handles still need a live comparison. [Adobe Free Transform guide](https://helpx.adobe.com/photoshop/desktop/crop-resize-transform/resize-adjust-resolution/transform-images-shapes-and-paths.html)

## Changes

- The native Transform section reads rotation and integer document bounds from the linked artwork's saved source transform. Its X and Y fields use those bounds for existing Move and Undo behavior. Free Transform starts from the same bounds.
- The rotation readout retains its existing symbol and gains a descriptive accessibility label and the current value in degrees.
- Photato document state exposes `layers[].smartObject.sourceGeometry` with the original affine transform, document-pixel bounds, and rotation. Clients can continue to use the layer's existing `transform` for the displayed preview and submit a document-space delta with `layer.transform`.
- Non-affine Smart Objects can omit affine geometry. The editor keeps its established rendered-bounds path for projected and imported appearance cases. Source content, cached pixels and file formats are shared with the existing Swift engine.

The Free Transform draft still uses a document-aligned rectangle. The stored source transform supplies the four artwork corners needed for an oriented frame, along with the local axes for side and corner drags. Adobe documents the original orientation as part of a Smart Object's retained transform. The remaining comparison is how those coordinates drive a second interactive transform. [Adobe Smart Object Reset Transform guide](https://helpx.adobe.com/uk/photoshop/desktop/create-manage-layers/smart-objects/reset-smart-object-transforms.html)

## Validation

The new tests in `LinkedSmartObjectGeometryWorkflowTests.swift` cover PSD/PSB reopen, a second transform, the actual native position field and one Undo, the documented loopback API, and rejection of affine readout for warped content.

The first build reached the test target and Swift rejected a local asynchronous test helper capturing an XCTest object. The second source isolates that helper to the main actor and creates its request helper there. The production source is identical between the two attempts.

All four focused Debug tests passed. For the live comparison, a disposable PSD contains a linked source whose eight placement coordinates were read independently from the file's Smart Object descriptor. They establish a 30° rotation and a document rectangle of 378 × 334 pixels at (212, 172). Build 658's live Properties panel read the expected X and Y and reported 0° for the rotation.

The signed build 659 reported 30.00° for Layer rotation through macOS's accessibility value description. The same live window reported W 378 px, H 334 px, X 212 and Y 172. The first probe checked the generic value attribute and found only the label. The follow-up read the correct attribute. The background window capture was blank, so the live evidence is the accessibility inspection.

All 1,472 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen.

In the native Properties accessibility tree, the same owned linked PSD now reads 30.00° where build 658 read 0.00°. The position and dimensions also match the bounds calculated from the PSD's stored placement. The native position-field test separately checked moving a transformed preview by its artwork's bounds, preserving fractional placement and producing one Undo.

[Qualification](SOURCE_PUBLICATION_659.md)
