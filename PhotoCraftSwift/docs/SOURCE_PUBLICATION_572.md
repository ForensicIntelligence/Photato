# Source checkpoint 572

Native Swift 0.3.0, build 572, 18 November 2026. The RGB32 Normal compositor now uses the operation order measured on each architecture. Intel rounds multiplication before addition in the affected color and alpha calculations. Apple Silicon retains its fused result. The same arithmetic covers the tested pass-through and isolated group opacity, nested groups, and grouped clipping.

The app's renderer and PSD and PSB serializer share the correction. The native Image Mode conversion now has a separate regression for the masked Display P3 Merge Visible and Grayscale case, built from the 5,120 samples saved by Photoshop on each architecture. The source-file and output-plane hashes are checked in that test. Photato API and compatible output retain their existing entry points and use the updated renderer.

All 705 selected tests passed in Debug, optimized Apple Silicon and optimized Intel under Rosetta. An independent reader compared 264,192 sample words across 20 RGB32 layer and group probes and the masked Display P3 conversion in each configuration. Every verified sample matched the corresponding Photoshop output. The RGB32 previews separately matched in PSD and PSB. The previous optimized Intel build differed at 47,363 of those words, including 291 in the Display P3 conversion.

Both slices of the local universal archive passed signature verification and the offscreen workspace check. The package declares macOS 14 as its minimum version. Physical Intel and macOS 14 runtime validation remain open.

The controls cover Normal raster layers and the supported Normal hierarchy. Independent HDR clipping, non-Normal layers, rich layers and whole-file byte identity remain open. [Adobe's HDR feature list](https://helpx.adobe.com/photoshop/desktop/adjust-color/hdr-and-channel-manipulation/features-that-support-32-bpc-hdr-images.html).

[Development record](DEVLOG.md#dev-step-572) · [Validation data and source fingerprints](HDR_NORMAL_COMPOSITING_REFERENCES_572.json)
