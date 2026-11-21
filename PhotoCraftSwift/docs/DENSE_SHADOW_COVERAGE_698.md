# Read raster alpha directly for regional Drop Shadows

Regional Drop Shadow preparation reads coverage directly from eligible raster tiles and applies the same mask sampler as the layer compositor. The spread filter skips covered samples whose distance cannot be improved by a neighbor.

The shifted map reads tiled alpha and evaluates the same mask in document coordinates. Transformed sources, clipped artwork and other ineligible inputs use the isolated compositor. The spread pass keeps the existing chamfer distances and noise continues to use document coordinates. [Photoshop effect options](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/apply-layer-effects/layer-style-effects-and-options-overview.html)

The native editor, Photato viewport API and supported Adobe-compatible composite operations share the renderer.

The coverage copy matched the isolated compositor in RGB8, RGB16 and RGB32, including translated layers and feathered pixel masks. Dense noisy Fit fixtures with and without transparent holes matched each architecture's build 697 Float32 composite and soft-proof samples byte for byte.

The software benchmark reduced a 24,576 × 768 RGB32 document to 311 × 31 pixels. On this Apple Silicon Mac, the fixture with transparent holes took 6.07 s for RGB Fit in build 697 and 3.82 s in build 698. Soft proof took 10.35 s and 8.60 s respectively.

475 of 476 selected tests passed in arm64 Debug, optimized Apple Silicon and Intel under Rosetta. The original PhotoCraft effect fixture failed with the same assertions in build 697. Both signed preview slices opened offscreen. Noisy previews still require per-pixel evaluation. Whole-document Fit on a maximum-size dense file still needs further work. The local Photoshop document query timed out, so Adobe shadow pixels and Fit sampling remain unverified. [Adobe API reference](https://developer.adobe.com/firefly-services/docs/photoshop/api/photoshop-v2/) · [Adobe file format](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/) · [Qualification](SOURCE_PUBLICATION_698.md)
