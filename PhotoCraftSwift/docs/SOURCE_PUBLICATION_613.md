# Source checkpoint 613

Native Swift 0.3.0, build 613, 19 November 2026. Large flattened Raw and PackBits RGB documents retain editable pixels, transparency and saved channels without staging all process planes.

The native file reader opened a 300,000 × 300,000 flattened RGB8 PSB with transparency and saved alpha in 13.58 seconds in one Apple Silicon Debug run. All 36,864 checked RGBA and 1,024 saved alpha words matched the independent input.

Build 612 reached a 768 KiB scratch limit on the 1,201 × 30,001 control. Build 613 opened it with three RGBA tiles and one saved-alpha tile.

All 961 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both extracted universal app slices passed signature and offscreen launch checks. The package declares macOS 14 as its minimum.

The maximum-size file used independently generated RGB8 PackBits data. Live Photoshop exchange and dense and ZIP maximum-size input remain open. [Adobe Large Document Format specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/).

[Development record](DEVLOG.md#dev-step-613) · [Validation data](PSD_FLATTENED_SPARSE_613.json).
