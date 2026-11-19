# Source checkpoint 585

Native Swift 0.3.0, build 585, 19 November 2026. Linear Dodge (Add), Subtract and Divide now work in supported raster clipping merges and stamps at 8, 16 and 32 bits per channel. [Adobe's HDR feature list](https://helpx.adobe.com/photoshop/desktop/adjust-color/hdr-and-channel-manipulation/features-that-support-32-bpc-hdr-images.html).

The tests compare 96 saved clipping results per architecture and exercise PSD reopen. They cover partial opacity, editable masks and the measured final scanline rounding on Apple Silicon. The desktop editor, native HTTP API and both local Adobe-compatible routes share the compositor.

All 99 focused Debug checks and 787 selected checks per configuration passed. Both slices of the extracted signed universal archive passed offscreen checks. The archive declares macOS 14 as its minimum.

The installed Photoshop reference application reports an ad-hoc signature. Reproduction on an Adobe-signed installation, physical Intel and macOS 14 execution remain open. Feathered contributing masks and broader rich clipping operations are still in development.

[Developer record](DEVLOG.md#dev-step-585) · [Validation data and source fingerprints](CLIPPED_ARITHMETIC_REFERENCES_585.json).
