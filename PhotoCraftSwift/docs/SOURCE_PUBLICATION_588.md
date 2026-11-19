# Source checkpoint 588

Native Swift 0.3.0, build 588, 19 November 2026. Layer-mask Feather now accepts 0–1,000 px in the native controls, Photato API and editable files. [Adobe layer-mask radius reference](https://developer.adobe.com/photoshop/uxp/ps_reference/classes/layer/).

The streamed filter matches 1,564 stored RGB32 words at 250 and 1,000 px from Apple Silicon and Rosetta Photoshop captures. Tests also verify native, PSD and PSB round trips and a requested region on a 300,000 × 300,000 canvas. The Photato API shares native history for mask-property edits.

All 850 selected checks passed across the suite and focused recheck in Debug, optimized Apple Silicon and Intel under Rosetta. Both extracted ad-hoc-signed universal slices passed offscreen checks. The archive declares macOS 14 as its minimum. The installed Photoshop 27.2.0 reference bundle uses an ad-hoc signature. Live field entry, physical Intel and macOS 14 execution remain open.

Fractional wide settings use discrete windows that approximate the requested variance. Exact fractional, affine and lower-depth results, remaining Intel rounding, fully sparse whole-canvas export and feathered clipping transactions remain in development.

[Developer record](DEVLOG.md#dev-step-588) · [Validation data and source fingerprints](WIDE_LAYER_MASK_FEATHER_588.json).
