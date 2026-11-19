# Source checkpoint 614

Native Swift 0.3.0, build 614, 19 November 2026. Large Raw, PackBits and ZIP RGB Photoshop layers, masks and saved channels retain sparse editable raster storage.

The native file reader opened an independently authored 300,000 × 128 RGB8 PSB with a ZIP-compressed layer, translated mask and saved alpha. All 36,864 checked component words matched. The Apple Silicon Debug run took 5.48 seconds.

Build 613 reached the 768 KiB scratch limit on the same control. Build 614 read the editable layer, mask and saved alpha into six tiles using 384 KiB of mapped storage.

All 962 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both extracted universal app slices passed signature and offscreen launch checks. The package declares macOS 14 as its minimum.

The maximum-width ZIP file was independently authored. Live Photoshop exchange, dense input and maximum-height ZIP remain open. [Adobe Large Document Format specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/).

[Development record](DEVLOG.md#dev-step-614) · [Validation data](PSD_SPARSE_ZIP_614.json).
