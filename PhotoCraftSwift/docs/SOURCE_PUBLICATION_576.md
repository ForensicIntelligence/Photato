# Source checkpoint 576

Native Swift 0.3.0, build 576, 18 November 2026. The shared native compositor now preserves the sampled normal 32-bit Photoshop raster results for prepared Merge Down, Merge Layers, Merge Visible, Stamp Layers and Stamp Visible. Desktop commands, recorded Actions and the two API interfaces use prepared layer output. [Adobe layer merge and stamp workflow](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/get-started-layers/merge-and-stamp-layers.html).

The editable layer records the later raster's contribution below the measured Float32 alpha threshold. An in-bounds zero-alpha pixel still participates when its layer opacity is nonzero. Intel flushes measured subnormal alpha results, including products at partial layer opacity. Existing source surfaces remain available to Undo. Stamps still preserve the original layers.

The independent scalar model matches 114,684 words per architecture from twelve Photoshop saves. The opacity study adds 205,108 matched words in a separate model. The native sample regression checks stored bounds, complete RGBA bytes and PSD save and reopen, with additional opacity captures. Fresh Intel captures replace Apple Silicon expectations in the native and API test on Intel. All 62 focused tests and 750 selected tests per build configuration passed. Both slices of the local universal validation archive passed offscreen checks and declare macOS 14 as their minimum.

The independently sampled raster masks, vector masks, clipped and grouped output, direct Core legacy merge, and physical Intel and macOS 14 runtime checks remain open.

[Developer record](DEVLOG.md#dev-step-576) · [Validation data and source fingerprints](HDR_LAYER_OUTPUT_REFERENCES_576.json)
