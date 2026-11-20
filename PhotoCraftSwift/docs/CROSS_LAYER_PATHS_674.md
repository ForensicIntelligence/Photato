# Select and transform paths across layers

The Paths panel lists saved paths, shape contours, and vector masks across the document. Click a row to focus it. Shift-click to select a range, or Command-click to toggle separate rows. The selected paths stay visible in the canvas. Clicking an anchor or segment on a companion path focuses it for editing. A Direct Selection marquee previews the points it encloses across the selected paths.

Command-T uses one bounding box and applies the same transform to the selected paths, contours, or anchors. Each path keeps its own selection scope. A locked target, an invalid anchor index, or a projective horizon across the shared bounds rejects the whole transform. A successful edit produces one Undo entry and leaves the pixel selection and unrelated layer content intact.

Use `paths.select` to select and focus explicit editable path targets through the Photato API. The optional document-coordinate marquee gives each target its own anchor selection. Use `paths.transform` with the selected targets and a shared matrix to apply one atomic edit. Native Actions version 77 records the target scopes and matrix, while earlier single-path Actions remain readable. [Photato Automation API](AUTOMATION_API.md) · [Adobe path selection](https://helpx.adobe.com/photoshop/desktop/draw-shapes-paths/create-shapes/select-paths-and-path-segments.html)

Live Photoshop hit ordering, isolation mode, and Warp across selected paths remain open.

## Validation

All 192 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

New tests cover panel ranges, Command-click, canvas focus, multi-path marquee, a shared transform and one Undo, Actions playback and authenticated API editing. All 12 earlier whole-layer vector mask outputs matched byte for byte.

[Qualification](SOURCE_PUBLICATION_674.md)
