# Source checkpoint 587

Native Swift 0.3.0, build 587, 19 November 2026. Aligned RGB32 layer masks use a staged square filter at whole-pixel Feather radii from 3 to 100 px.

The implementation keeps editable mask samples and evaluates the staged filter in bounded tiles. It matches 34,975 stored coverage samples from 21 Apple Silicon Photoshop captures. The references include three scanline widths, ordinary and off-canvas masks, textured data and impulses. The tests exercise a requested region of a 300,000 × 300,000 document.

All 844 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. Both extracted ad-hoc-signed universal slices passed offscreen checks. The archive declares macOS 14 as its minimum. The installed Photoshop 27.2.0 reference bundle also uses an ad-hoc signature. Reproduction on an Adobe-signed installation, physical Intel and macOS 14 execution, and live editing remain open.

The 250 and 1,000 px controls matched the model independently. The app range stays at 100 px while the larger path is prepared. Fractional schedules, more Intel output, RGB8/16, affine masks and feathered clipping transactions remain in development. [Adobe layer-mask radius reference](https://developer.adobe.com/photoshop/uxp/2022/ps-reference/classes/layer).

[Developer record](DEVLOG.md#dev-step-587) · [Validation data and source fingerprints](RGB32_AREA_FEATHER_587.json).
