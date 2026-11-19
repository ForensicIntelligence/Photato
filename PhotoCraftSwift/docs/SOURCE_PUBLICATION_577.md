# Source checkpoint 577

Native Swift 0.3.0, build 577, 18 November 2026. Prepared RGB32 Normal layer output correctly skips raster samples where an enabled stored pixel mask has zero coverage. Intel flushes subnormal mask products, including a product from a mask sample of one. This applies to the shared native layer merge and stamp compositor.

The native save and reopen check uses eight separately saved Photoshop raster-mask outcomes per architecture. The independent arithmetic comparison matches all 51,624 words per architecture and covers binary masks and stored coverage from feathered selections. For a 300,000 × 300,000 sparse document, the focused test allocates only the two contributing render patches, including the translated mask.

All 64 focused Debug tests and 752 selected tests in each of Debug, optimized Apple Silicon, and optimized Intel under Rosetta passed. Both slices of the extracted universal archive passed strict signature verification and offscreen workspace checks. The package declares macOS 14 minimum.

Vector masks, live Density and Feather settings, independent clipping, rich layer combinations, live menu dispatch, and physical platform qualification remain open.

[Developer record](DEVLOG.md#dev-step-577) · [Validation data and source fingerprints](HDR_LAYER_MASK_REFERENCES_577.json)
