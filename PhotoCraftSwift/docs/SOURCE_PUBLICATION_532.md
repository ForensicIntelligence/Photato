# Source checkpoint 532

Native Swift 0.3.0, build 532, 17 November 2026. The incremental renderer can reuse completed Float32 composite tiles that are already exact for the destination grid. It copies only the affected rows at unaligned edges, uses the source's implicit pixels for missing tiles, and preserves transparency and HDR samples. Cross-format patches and samples requiring normalization use the existing pixel setters. If an exact replacement is rejected or cancelled, the prior snapshot stays intact.

The 92 focused methods and seven Photoshop-reference methods pass in Debug, optimized Apple Silicon and translated Intel. The two new tests exercise mapped tile sharing, the edge-row path, independent copies, opacity proof invalidation, sparse clearing and failure atomicity. The Photoshop checks compare merged planes from 20 owned RGB32 documents with retained Photoshop 2026 samples and exercise regional rendering on those fixtures. A separate harness assembles each of those documents from smaller composite regions through the new tile installer. It matches all 1,036,288 reference bytes on each optimized architecture. This evidence covers the represented samples, layer cases and supported compression tests. [Fixture provenance](../Tests/PhotoCraftImagingTests/Fixtures/rgb32-groups/provenance.json). Physical presentation, live Photoshop interaction in this checkpoint and full-file Photoshop parity remain open.

## Layered Brush measurements

Both versions use an owned 6000 × 4000 canvas with two tone adjustments and 240 ordinary brush samples. The run order is 531, 532, 532, 531. Patch installation is timed separately from rendering the patch. The full and reduced preview and Float32 working composite sample hashes match across all four runs. The hosted tests exercise ordinary AppKit canvas drawing at 12.5% zoom with generated 120 Hz input, retaining all samples.

| Stage | Build 531 median | Build 532 median | Build 531 p95 | Build 532 p95 |
| --- | ---: | ---: | ---: | ---: |
| Install a composite patch | 0.64 ms | 0.12 ms | 0.96 ms | 0.16 ms |
| Brush batch through composite | 4.88 ms | 4.32 ms | 6.94 ms | 6.01 ms |
| Hosted preparation to ready | 6.36 ms | 5.66 ms | 11.73 ms | 9.47 ms |
| Hosted input to AppKit draw | 11.78 ms | 12.74 ms | 18.52 ms | 24.99 ms |

Individual hosted input-to-draw p95 readings were 20.61, 16.43 ms for build 531 and 24.04, 25.94 ms for build 532. In five runs per build with the original main-actor input driver, the median run p95 rose from 20.21 to 25.36 ms. Input spacing also widened from 13.13 to 17.13 ms, and time before preview preparation increased from 5.10 to 13.79 ms.

An independently scheduled 120 Hz driver replaced the timing test object and used the original app object files from each optimized build. Both builds received the same stroke with comparable input spacing (9.67 and 9.67 ms at p95). Across three runs per build, the median run p95 from input enqueue to AppKit draw was 27.92 ms on 531 and 22.60 ms on 532. The original driver's longer tail remains an open scheduling finding. Physical input and physical 60 fps remain unmeasured.

The universal archive passes architecture, macOS 14 deployment metadata, signature, resource and extracted archive checks. Live launch of the packaged app, actual macOS 14 and physical Intel, and arbitrary Photoshop documents remain unverified. The application still uses the existing native archive, shortcuts, command and API contracts.

[Development record](DEVLOG.md#dev-step-532) · [Measurements and reference methods](COMPOSITE_REGION_532.json) · [Frozen source](SOURCE_SNAPSHOT_532.json)
