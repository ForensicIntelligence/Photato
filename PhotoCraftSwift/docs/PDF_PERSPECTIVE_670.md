# PDF Smart Object Perspective

Perspective and Distort can keep a PDF page editable as a Smart Object. The original PDF, page, crop, and logical artwork corners remain available when Photato saves or reopens a supported PSD or PSB. A linked file keeps its cached perspective and source reference until an approved relink makes the original available. [Adobe’s Free Transform guide](https://helpx.adobe.com/photoshop/desktop/crop-resize-transform/resize-adjust-resolution/transform-images-shapes-and-paths.html)

The PDF renderer chooses a raster density from an upper bound on the homography's local magnification. It samples that denser raster through the same inverse projection and uses the original source rectangle for the output bounds. The sampling grid does not move the editable corners or unlinked masks. Free Transform's neutral Warp record continues to carry interpolation without forcing a mesh render. Rasterize Layer uses the same source sampling, so committing to pixels preserves the visible placement.

The existing `layers.transform` command accepts the same nine document-space matrix coefficients as the native editor. Its PDF source, projective geometry and exported PSD or PSB stay editable. The Adobe-compatible manifest reports the placed quadrilateral. These operations use the existing document, API and archive representations.

The owned Photoshop-authored PDF placement fixture is `Tests/PhotoCraftImagingTests/Fixtures/pdf-psd/photoshop-art-page.psd`. Previously, an enlarged 108 × 72 PDF placement stayed at its initial cache density. It differed by 1,687 of 593,920 composite bytes against a fourfold source-grid comparison. Both Photoshop containers rejected the editable perspective output. Photoshop 2026 answered its version query as 27.2.0. Its read-only document query timed out. The projected variants and their byte comparisons are therefore Photato render and interchange evidence. A Photoshop-authored projected PDF reference, live render comparisons, and dense maximum-size PDF capacity remain open.

## Validation

All 109 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen.

The owned Photoshop PDF evidence matched a fourfold source grid across all 593,920 composite bytes. 4 of 4 perspective outputs matched byte for byte across the three Photato configurations. All eight prior PDF Warp outputs also matched. The linked and unlinked affine mask checks passed.

[Qualification](SOURCE_PUBLICATION_670.md)
