# Reopen perspective Smart Objects and continue editing

## 20 November 2026

An embedded Smart Object that had been distorted in Photato could stay editable in the native format. Editable PSD and PSB output rejected the projected layer. A fresh Free Transform draft then showed an axis-aligned rectangle around the artwork. This checkpoint connects the document's stored projective placement to the existing Free Transform handles and Photoshop file codec. [Photoshop Smart Object behavior](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/smart-objects/smart-objects-overview-and-benefits.html) · [Photoshop Free Transform controls](https://helpx.adobe.com/photoshop/desktop/crop-resize-transform/resize-adjust-resolution/transform-images-shapes-and-paths.html)

The PSD reader restores the effective corners from `nonAffineTransform` when present and maps the original source rectangle to them. The writer emits the bounding rectangle and the projected corners in the corresponding placed-layer records. It reuses the original corner words when the saved placement is unchanged. The imported layer's cached render can be displayed before an edit. A placement or source change makes that cache ineligible and the native renderer uses the original artwork again. Ordinary affine placements keep the existing serialization. [Adobe placed-layer format](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/) · [Reported Photoshop mockup coordinates](https://github.com/storytold/photocraft/issues/579)

Free Transform begins with the saved artwork corners and uses the inverse placement to recognize points inside the frame. The rotation field displays the top edge's angle. The reference point follows the source, and a move or rotation can carry an affine delta without rebuilding a perspective map. Projective corner edits continue through the existing layer command, history and Actions paths. The Photato API reports the source homography and preview corners. The Adobe-compatible manifest reports the composed document-space corners.

## Validation

The layout tests use owned artwork with a scaled copy of the public mockup coordinates. They check PSD and PSB reopen, original bytes, numeric corner records, pixel mask placement, cached rendering, invalid quadrilaterals, repeated transforms and API geometry. Photoshop 27.2.0 answered a version query. Its document count and scripting checks both timed out before opening any fixture. Direct Photoshop rendering and transform-control comparisons remain open. Projective linked files, projective PDF sources and non-identity Warp descriptors still need editable Photoshop-file coverage.

The first Debug run passed both new file-codec tests and the second Distort and manifest test. The hit-testing test had no window viewport, so its handle radius covered points intended for move and rotate. The revised test uses a real AppKit window with an explicit zoom. The transform-reference test also asserted a 267-command catalog size, which already reported 276 on checkpoint 664. The updated assertion checks that `transform.reference` is registered once.

The revised candidate passed all 31 focused tests. A separate reader checked six generated files across PSD and PSB. It matched the original PNG bytes in each file, verified the base rectangle and effective corner records, verified exact corner words on unedited resaves, and checked their three-pixel horizontal and two-pixel vertical offsets after a repeat move. The standalone fixture tool needed normal macOS ImageIO type resolution outside the command sandbox.

1,507 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. One additional RGB32 test passed on Apple Silicon and reproduced the previous Intel result. Both slices of the signed macOS 14+ universal preview launched offscreen.

The four new tests exercised editable PSD and PSB output, original source bytes, mask position, cached render, malformed corners, hit-testing and repeat Distort. A separate reader checked six files and the raw double-precision corner records.

[Qualification](SOURCE_PUBLICATION_665.md)
