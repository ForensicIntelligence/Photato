# PDF Smart Object Warp

A PDF page placed as a Smart Object keeps its original bytes, page and crop while the Warp controls stay editable. Adobe documents Warp for embedded and linked PDF artwork. Photato continues to use its existing Warp sheet and `layer.warp` command, with the same preview, commit, and Undo behavior. [Adobe PDF placement guide](https://helpx.adobe.com/photoshop/desktop/app-integrations/place-illustrator-files-or-pdf-in-photoshop.html)

The original PDF is rerasterized before Warp at a density estimated from the largest local magnification of the triangles used by the renderer. Sampling uses the new raster grid while the logical mesh, projected placement, and document-space masks retain their coordinates. The renderer uses the existing full-source PDF raster budget. Rasterize Layer, PSD compatibility previews, Smart Filter caches, and the editor and API use the same sampling path.

The PSD and PSB codecs retain the vector original, page/crop, supported Warp settings and their placed quadrilateral. A cached external PDF can remain linked without reading its path, and approved relink applies the saved Warp to the recovered original. Native archive and API schemas retain the existing Warp and PDF representations. Adobe-compatible manifests report the existing placed quadrilateral. The published Adobe v2 interface has no dedicated Warp operation.

The owned Photoshop PDF reference is `Tests/PhotoCraftImagingTests/Fixtures/pdf-psd/photoshop-art-page.psd`. Before this change, at threefold magnification, adding an identity mesh replaced its 324 × 216 render with a 108 × 72 cache and changed 1,278 of 353,152 composite bytes. Photoshop's live scripting interface timed out during this checkpoint. The reference was authored in Photoshop with PDF placement. The Warp and relink variations used for this checkpoint are created by Photato.

PDF image selection and the nondefault PDF antialias policy remain native archive features. Standalone PDF perspective interchange, a fresh Photoshop-authored warped-PDF fixture, exact Photoshop rerendering, and full dense maximum-size PDF rerasterization remain open.

## Validation

All 88 selected tests passed in Apple Silicon Debug, optimized Apple Silicon and optimized Intel under Rosetta. Both slices of the signed macOS 14+ universal preview launched offscreen.

The owned Photoshop PDF fixture retained every composite byte when a neutral Warp mesh was added after 3× enlargement. Four new tests cover local PDF magnification, mask coordinates, rasterization, linked relink and native/HTTP interchange. 8 of 8 fixture outputs matched byte for byte across the three Photato configurations. Twenty-three supplemental Debug cases passed. Filtered PDF exports reopened with identical composites. All three prior raster Warp files and eight Intel RGB32 PSDs matched the preceding outputs byte for byte.

[Qualification](SOURCE_PUBLICATION_669.md)
