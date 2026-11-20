# Warp editable paths

Select a saved path, vector mask or shape contour in the Paths panel. Shift selects a range, and Command toggles individual targets. You can Warp full paths, components or selected anchors. Choose **Edit > Transform > Warp** from the selection, or start Free Transform with Command-T and choose **Warp** in the Options bar or canvas menu. Any pending Free Transform is applied before Warp in the same edit. The document updates after Apply or Return. Escape cancels the entire pending edit.

Use the same presets, custom grids and Cylinder controls as raster Warp. The main canvas keeps its own pan and zoom. Choose a grid control and drag to reshape the selected geometry. Use Split to add a mesh boundary. The selected anchor indices update when the deformation needs additional editable Bézier knots. Unselected anchors and handles are preserved. Warped shape geometry may become an editable contour in place of live primitive controls. Native documents, PSD and PSB store the resulting curves.

Use `paths.warp` with the same `targets` list as `paths.transform` and a Warp `settings` object. An optional nine-value row-major `matrix` precedes Warp. The source frame defaults to the bounds of the projected selection. Mesh points and optional source bounds use document pixel coordinates. The result includes `pathTransformSelections`. Photato Actions version 78 records this operation.

The fitted path uses a sampled 1/128 pixel acceptance threshold with additional subdivision at mesh boundaries. Adobe documents the entry point and editing workflow. Photoshop-authored Warp output, switching from edited Warp back to Free Transform, and physical canvas responsiveness remain open. [Adobe Free Transform instructions](https://helpx.adobe.com/photoshop/desktop/crop-resize-transform/resize-adjust-resolution/transform-images-shapes-and-paths.html)

## Validation

All 198 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

The six new tests cover split tangents, a dense analytic curve comparison, untouched grids, locked and stale edits, continuous drag preview, canvas cancel and commit, Actions replay, authenticated automation, and editable PSD and PSB paths. All 12 earlier whole-layer vector mask outputs still match byte for byte.

[Qualification](SOURCE_PUBLICATION_675.md)
