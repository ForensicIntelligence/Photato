# Smart Object placement at source print size

## 20 November 2026

Photato’s Place Embedded and Place Linked used source pixel dimensions even when the source and the destination both had print resolutions. For example, a 600 × 600 pixel asset at 300 pixels per inch covers 2 × 2 inches. Placement in a 72 ppi document should therefore cover 144 × 144 document pixels. Adobe describes centered placement, preservation of source resolution and a proportional fit for oversized artwork. A published Photoshop user reports reproducing this exact size mismatch on both Mac and Windows. [Adobe placement guide](https://helpx.adobe.com/photoshop/desktop/create-open-import-images/import-files/place-a-file-in-photoshop.html) · [Adobe resolution reference](https://helpx.adobe.com/photoshop/desktop/crop-resize-transform/resize-adjust-resolution/image-size-resolution-and-resampling.html) · [Original reproduced case](https://community.adobe.com/questions-712/is-it-possible-to-place-images-at-their-actual-original-100-pixel-dimensions-while-ignoring-resolution-1170222)

The installed Photoshop session timed out on a read-only version and document-count request. The placement math follows the published resolution model and reproduced behavior. Exact Adobe centering, interpolation, format-specific metadata rules, and pixel equivalence remain open.

## Changes

- Desktop Place Embedded and Place Linked derive the starting transform from the source’s physical size and the destination ppi. Resize Image During Place fits oversized artwork after converting to destination pixels. Skipping the transform preview uses the same sizing.
- PDF pages use the selected box in points. The chosen render resolution determines cache density. A PDF image uses its retained pixel dimensions and resolution like other raster sources.
- Embedded uploads, PDF uploads, shared-document placement and approved linked placement expose `sizing: "physical"`. Omitted sizing preserves existing API pixel sizing. Fit and an explicit transform still apply after the initial sizing. Frame placement and replacement retain their existing geometry rules.
- Placement retains the original bytes and resolution in the Smart Object. The operation is one undoable transaction and uses the same sampling and preview pipeline.

The existing integer translation convention is retained while the initial dimensions use physical size. Documents without an explicit resolution use their existing 72 ppi fallback. Firefly v2 resource jobs retain their published transform and bounds contract. [Firefly Smart Object workflow](https://developer.adobe.com/firefly-services/docs/photoshop/guides/workflows/smart_object/)

## Related API gap

Adobe's current OpenAPI schemas for Smart Object adds, edits and transforms match the seven corresponding schemas already pinned in the repository. Photato accepts `none`, `fit` and `fill`. The adapter still rejects `custom`, which Adobe documents for jobs that specify an offset, dimensions, rotation, skew or anchor. That work is separate from physical sizing in the desktop editor. The schema confirms the request fields. Live service comparisons are still needed for their geometry and defaults. [Adobe OpenAPI source](https://github.com/AdobeDocs/ffs-photoshop-API/blob/main/static/photoshopv2-api.json) · [Transform guide](https://developer.adobe.com/firefly-services/docs/photoshop/guides/photoshop-v2-beta/v1-to-v2/layer-operations-advanced)

## Qualification

All six new Debug tests passed. They cover higher and lower destination ppi, post-sizing fit, exact PDF points at multiple cache densities, native and HTTP placement, source preservation, Undo and invalid placement options.

The independent Debug fixture read matched all 1,440,000 raw merged sample bytes in each Photoshop container. The 600 × 600 source at 300 ppi occupied document pixels `[228, 372)` on both axes in the 72 ppi destination. The remaining pixels match the white background and the entire alpha plane is opaque.

All 1,463 selected tests passed in Apple Silicon Debug, optimized Apple Silicon, and optimized Intel under Rosetta. Both slices of the ad hoc–signed macOS 14+ universal preview launched offscreen.

The independent raw PSD and PSB composite check recovered a 144 × 144 pixel placement of the 600 × 600 pixel, 300 ppi source in a 72 ppi document. Both architectures wrote byte-identical native, PSD and PSB files. Both optimized builds also passed the 1.18 GB linked PSB workflow.

The Debug build used the established Swift compiler workaround. Physical Intel, macOS 14 runtime and live Adobe placement comparisons remain open. [Qualification and hashes](SOURCE_PUBLICATION_657.md)
