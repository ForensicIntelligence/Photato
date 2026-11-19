# Float32 underflow during Normal blending

The two PSDs are procedural inputs created for Photato and available under
MIT OR Apache-2.0. Their colors include signed zero, subnormal and smallest
normal Float32 values. Each document contains a Normal raster overlay above
an opaque or translucent raster backdrop.

The reference hashes were captured after Merge Visible in Photoshop 2026
27.2.0 on Apple Silicon and Intel under Rosetta. The comparison visits
positive-coverage pixels in top-left row-major order and writes straight
R, G, B and alpha as big-endian Float32 words. Alpha is one in a composite
with an implicit opaque background. The test uses the sampled layer
coverage so cropped transparent edges and the independent zero-coverage
blending cases remain separate investigations.

The `opaque-source` deck covers twelve RGB32 documents with ordinary or
grouped clipping. An opaque source spans the canvas in the copy controls.
One translucent pixel in a near or far position, a cropped offset source,
and an off-canvas translucent sample test the boundaries of that behavior.
The two PSDs over a translucent backdrop check which alpha the copy retains.
Each reference hash covers all straight RGBA words in Photoshop's saved Merge
Visible result.

The `backdrop-alpha` deck covers sixteen fully opaque sources over opaque,
uniform, or varying backdrop alpha. It includes three-layer normal stacks
and grouped clipping, which retains the base layer's alpha. The reference
hashes from Photoshop's Merge Visible result cover all straight RGBA words.
