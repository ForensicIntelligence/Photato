# Source checkpoint 610

Native Swift 0.3.0, build 610, 19 November 2026. Layered PSD and PSB can retain saved alpha, spot, and Quick Mask planes when their Version Info declares the merged preview absent.

A synthetic sparse 300,000 × 300,000 PSB opened with the exact editable raster in 3.5 ms on Apple Silicon Debug. The reader skipped 270 GB of unused logical raw preview data.

The native reader matched all 4,016 editable-layer and saved-channel sample words across 80 independently assembled PSD and PSB controls. A loopback regression covered Photato import, truncated-input rejection, and both job interfaces.

All 957 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both extracted universal app slices passed signature and offscreen launch checks. The package declares macOS 14 as its minimum.

The controlled reader fixtures are synthetic. Adobe-authored compatibility-off output with saved channels or higher bit depths, live Photoshop interoperability and physical platform coverage remain open. [Adobe file format specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/).

[Development record](DEVLOG.md#dev-step-610) · [Validation data](PSD_AUXILIARY_PREVIEW_610.json).
