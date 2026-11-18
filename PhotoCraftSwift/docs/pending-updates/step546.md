<a id="dev-step-546"></a>

## 2026-11-17 — Write changed canvas bytes directly

The 24 MP display probe isolated the 5,000 px first-brush update. Building a temporary canvas crop took 196 ms and packing it to RGBA took 104 ms. The retained image is already stored as a row-strided RGBA8 buffer.

Surface.swift reads intersecting source tiles and writes the existing straight-alpha sRGB conversion directly to the matching rows. It shares the RGBA8 encoding with RasterIO and handles implicit pixels, mapped tiles and extended linear samples. CanvasRasterPreview.swift preserves the existing ColorSync conversion for custom working profiles. CanvasReducedPreview.swift uses exact integer sums for whole-pixel area boxes, with the existing weighted routine for fractional boxes and boxes beyond the integer accumulator bound.

CanvasRasterPreviewTests.swift checks full and regional bytes, partial edges, mapped sources, extended linear input, a custom profile and retained image lifetime. It checks whole-pixel area filtering against independent integer alpha-weighted sums. Working document samples and automation calls continue to use the same renderer and formats.

All 80 raw outputs match build 545 on both optimized architectures. The two ColorSync buffers retain their existing two one-level red differences between architectures. All 392 selected methods passed in all three configurations. Both packaged binaries passed the offscreen workspace check.

At 5,000 px, Apple Silicon display conversion went from 357 to 103 ms. The paired AppKit first draws were 913 and 647 ms. Physical editing cadence remains open. [Qualification](SOURCE_PUBLICATION_546.md).
