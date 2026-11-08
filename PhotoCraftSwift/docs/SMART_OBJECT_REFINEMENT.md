# Select and Mask on Smart Objects

Select a Smart Object and choose Select > Select and Mask, or press Command-Option-R. The existing workspace can refine its selection or ordinary layer mask. Source pixels, embedded data and Smart Filters remain editable.

Selection and Layer Mask outputs keep the Smart Object. Copy outputs use the existing renderer to create raster results, including current Smart Filter/warp/PDF rendering where supported. The new copy gets the refined mask or baked transparency; the original remains intact. Decontamination changes rendered output pixels only. Existing geometry/styles, one Undo and archive behavior are retained. Locked sources permit read-only selection/new-document preparation; existing same-document modification restrictions still apply.

The existing `selection.refine` API accepts the same Smart Object layer ID, settings, strokes, source mask and output choices. New-document outputs require document-transfer permission, return201 and preserve source history. Captured preparation cannot publish after cancellation, stale source, sharing revocation or a lifecycle change. No new Adobe route or unverified desktop descriptor is claimed. Smart Filter masks remain outside Select and Mask, and Focus Area retains its ordinary-raster restriction.

## Reference and tests

In Photoshop 2026, an owned 64 × 48 RGB8 image was converted to a Smart Object. Select and Mask accepted it and offered all six outputs. Layer Mask retained Edit Contents; New Layer with Layer Mask created a raster copy. Both documents were saved as owned references and closed cleanly. The neutral full-canvas mask agrees with all 3,072 captured bytes. This is not a refined-edge/model/default oracle.

The reference exposed an existing PSD importer rejection of an empty Anno block inside the embedded Smart Object. The known nonrendering block is now preserved opaquely and exported unchanged in PSD/PSB. It also survives native archives. Reference files were kept intact. Note interpretation/editing and geometry updates remain separate work. The next import failure identified a documented hasRealMergedData=false flag in the embedded PSB. Decoded layers now supply its image; a complete known declaration is required. Ordinary cache validation is unchanged, and absent layers/auxiliary planes cannot be discarded.

All 127 selected Debug methods pass, including 17 new source/output/native/HTTP/history/guard/annotation tests. The first build caught two fixture writes to a read-only property; the second ran123 of 124successfully before the annotation import fix. The next attempt passed 124 of 125 before the missing-composite declaration was handled. Two further tests check that path and its strict negative cases. Every attempt and its source/products are retained. An isolated Debug app passes minimum14/entitlements/signature/payload checks and native import; interactive refinement remains pending. Normal 467 joins a later stable batch; the latest optimized universal remains466.

Full S04, Refine Hair/Adobe aware algorithms, independent nonneutral output/defaults, broader source/target/capacity contexts, physical platforms,60fps and earlier failures remain open. [Evidence](SMART_OBJECT_REFINEMENT_467.json).
