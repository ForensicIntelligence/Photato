# Source checkpoint 607

Native Swift 0.3.0, build 607, 19 November 2026. Large Photoshop layers sample across their height and retain sparse storage when their channels use raw or RLE.

The editable 300,000 × 300,000 RLE PSB with paint across its first row reopened in 1.72 s on Apple Silicon and 2.70 s under Rosetta. All raster bits matched. Its 4,690 retained tiles occupied about 293 MiB.

The raw and mixed-compression controls each went from 8,911 mapped tiles to 21. Row inspection preserved the live cursor and continued to reject malformed input in both PSD and PSB.

All 940 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both extracted universal app slices passed signature and offscreen launch checks. The package declares macOS 14 as its minimum.

A wide painted stroke still triggers the slower export path in this build. Dense and ZIP maximum-size files, live Photoshop cross-open, and physical Intel and macOS 14 runtime remain open. [Adobe file format specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/).

[Development record](DEVLOG.md#dev-step-607) · [Validation data](SPARSE_LAYER_SAMPLING_607.json).
