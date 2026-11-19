# Source checkpoint 584

Native Swift 0.3.0, build 584, 19 November 2026. Supported clipping merges and stamps preserve the editable base pixel mask and apply contributing masks at 8, 16 and 32 bits per channel. The native editor, Photato HTTP API and both local Adobe-compatible job routes share the implementation. [Adobe layer masks](https://helpx.adobe.com/photoshop/desktop/create-masks/layer-masks/add-layer-masks.html).

The tests compare 119 saved clipping outputs per architecture and exercise PSD reopen. They cover ordinary, translated and disabled masks, mask Density and partial Normal and other supported layer opacities. Fifteen separate Float32 Density controls cover 53,967 samples per architecture. A translated one-pixel mask on a maximum-size sparse canvas allocates one output tile.

All 94 focused Debug checks and 782 selected checks per configuration passed. Both slices of the extracted signed universal archive passed offscreen checks. The archive declares macOS 14 as its minimum.

The installed Photoshop reference application reports an ad-hoc signature. The comparison covers the recorded files. Reproduction on an Adobe-signed Photoshop installation, physical Intel and macOS 14 execution remains open. Feather on contributing masks and other rich masked clips are still in development.

[Developer record](DEVLOG.md#dev-step-584) · [Validation data and source fingerprints](CLIPPED_PIXEL_MASK_REFERENCES_584.json).
