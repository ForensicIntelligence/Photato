# Switch between path Warp and Free Transform

Select editable paths, shape contours or vector masks. Start Free Transform with Command-T, then select Warp in the options bar or the canvas menu. Select Free Transform in Warp to place, rotate or distort the curves again. You can switch back to the same mesh and adjust it with the new placement visible.

Return and Apply commit the whole edit. Escape and Cancel discard all pending changes. The options bar keeps Apply and Cancel visible in both modes and keeps Warp visible in Free Transform when the other controls scroll. The selected geometry, including new editable curve segments, remains part of the same Undo.

`paths.warp` accepts `matrix` before Warp and optional `matrixAfter` after it. Both use row-major homogeneous matrices in document pixel coordinates. The state reports the active mode and the accepted matrix after Warp. Actions version 79 can store both matrices. Existing version 78 Warp actions remain readable.

All 202 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ preview launched offscreen.

The new tests exercise mixed transform order, a horizon between paths, changing a mesh handle after a perspective edit, mode switching with Apply and Cancel, Actions replay, and authenticated API validation. All 12 earlier whole-layer vector mask outputs match byte for byte.

9 of nine owned mixed-transform PSD, PSB and RGBA outputs agree byte for byte across the three builds. 2 of three native archives also match. The largest recorded change in editable curve coordinates across the builds is 1.48e-11 pixels.

Photoshop-authored path output, exact guide and mode behavior in Photoshop, and physical canvas speed remain open. [Adobe Free Transform instructions](https://helpx.adobe.com/photoshop/desktop/crop-resize-transform/resize-adjust-resolution/transform-images-shapes-and-paths.html) · [Qualification](SOURCE_PUBLICATION_676.md)
