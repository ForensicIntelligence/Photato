# Marquee selection for path anchors

Select a saved path, vector mask, or shape contour, then choose Direct Selection. Drag from a clear area around the anchors you want to select. The enclosed anchors highlight during the drag. Their selection takes effect when you release the mouse. Hold Shift when starting the drag to add anchors. Press Escape to cancel, or click an empty area to clear the anchor selection.

Drag in either direction. The rectangle includes anchors on its border. Press Command-T to transform the selected anchors. The marquee keeps the current pixel selection and creates no document history entry. Clicks on visible handles, anchors and segments still start their existing edits or selection gestures.

The Photato API accepts a document-coordinate `marquee` with `start` and `end` points through `path.configure`. Set `extend` to add to the current anchor selection. Supply `pathID`, `layerID` for a shape, or `vectorMaskLayerID` to select an explicit target. Read `paths.transformSelection` for the committed indices. During a native drag, `paths.marqueePreview` reports the temporary selection. [Photato Automation API](AUTOMATION_API.md) · [Adobe path selection](https://helpx.adobe.com/photoshop/desktop/draw-shapes-paths/create-shapes/select-paths-and-path-segments.html)

One marquee applies to the active path. Simultaneous cross-layer path selection and live Photoshop comparisons of edge, modifier, and hit-order behavior remain open.

## Validation

All 186 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

New tests exercise reverse drags, Shift, Escape, focus loss, existing pixel selection, Command-T and authenticated path selection. All 12 earlier whole-layer vector mask outputs matched byte for byte in each configuration.

A 4,096-anchor Core benchmark measured 0.231 ms p95 for additive selection on Apple Silicon and 0.363 ms under Intel Rosetta. Canvas painting and display refresh were outside this measurement.

[Qualification](SOURCE_PUBLICATION_673.md)
