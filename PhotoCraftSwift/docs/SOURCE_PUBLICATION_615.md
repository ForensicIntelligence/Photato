# Source checkpoint 615

Native Swift 0.3.0, build 615, 19 November 2026. Large editable and flattened Grayscale, CMYK and Lab Photoshop files keep unchanged separation samples implicit.

The native file reader opened an independently authored 300,000 × 300,000 Grayscale/16 PSB and matched all 18,432 checked gray and alpha words. The Apple Silicon Debug run took 2.61 seconds and retained 24 KiB of mapped component samples.

Build 614 exhausted a 384 KiB scratch limit on the smaller 1,531 × 5,491 control. Build 615 opened it under that allowance and matched all 19,842 checked words.

All 963 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both extracted universal app slices passed signature and offscreen launch checks. The package declares macOS 14 as its minimum.

The maximum-size Grayscale file was independently authored. Live Photoshop exchange, full-size dense files, masks and maximum-size CMYK/Lab remain open. [Adobe Large Document Format specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/).

[Development record](DEVLOG.md#dev-step-615) · [Validation data](PSD_SPARSE_NATIVE_615.json).
