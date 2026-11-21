# Reduce Fit and proof previews for large uniform Drop Shadows

Large RGB previews reuse uniform Drop Shadow spans while rendering the edges and output affected by sparse raster or mask changes. Eligible reduced HTTP viewports use the same path.

A constant span contributes one representative sample across its exact area. Close to a shifted edge the renderer supplies all original samples. The corrections account for both a changed raster or mask tile and its displaced shadow footprint. The numerical reduction uses premultiplied color. [Photoshop effect options](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/apply-layer-effects/layer-style-effects-and-options-overview.html)

RGB8, RGB16 and RGB32 reductions with raster and mask edits matched the streamed renderer. The native Fit view and explicit HTTP composite, green-channel and soft-proof PNGs matched on a 300,000 × 300,000 document. The 70,000 × 520 benchmark reproduced each architecture's build 696 Float32 composite and soft-proof samples byte for byte. All 12 translated and partially covering layer cases matched the streamed Float32 output in each tested configuration.

On this Apple Silicon Mac, RGB Fit for the 70,000 × 520 source took 11.95 s in build 696 and 0.06 s in build 697. Soft proof took 17.78 s and 0.25 s. The maximum-size candidate Fit took 0.05 s for the owned uniform fixture with local raster edits. These measurements cover software reduction.

474 of 475 selected tests passed in arm64 Debug, optimized Apple Silicon and Intel under Rosetta. The same original PhotoCraft effect fixture failed with identical assertions in build 696. Both signed preview slices opened offscreen. A coordinate-dependent shadow, such as one with noise, still needs the ordinary renderer. Broad edited areas and unsupported stacks also retain their prior rendering path. The local Photoshop document query timed out, so Adobe Fit sampling and Adobe shadow pixels remain unverified. [Adobe API reference](https://developer.adobe.com/firefly-services/docs/photoshop/api/photoshop-v2/) · [Adobe file format](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/) · [Qualification](SOURCE_PUBLICATION_697.md)
