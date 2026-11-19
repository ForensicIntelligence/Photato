# Source checkpoint 605

Native Swift 0.3.0, build 605, 19 November 2026. Large sparse Photoshop files reuse merged pixels and identical rows during export.

The 300,000 × 131 RLE file was byte-identical to build 604. Save time went from 10.97 s to 0.30 s on Apple Silicon and from 17.54 s to 0.34 s under Rosetta.

Photato saved the 11.26 GB editable solid-fill PSB at 300,000 × 300,000 pixels in 3.22 s and reopened it in 2.12 s. An independent reader checked all 1,200,000 merged row lengths and 140 sampled channel values. These were single runs on the same Mac.

All 932 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. A separate Debug run passed 24 file I/O checks. Both extracted universal app slices passed signature and offscreen launch checks. The package declares macOS 14 as its minimum.

The 300,000 × 300,000 control used an editable solid fill. Maximum-size nonuniform raster imports, dense or rich-layer performance, live Photoshop cross-open, and physical Intel and macOS 14 runtime remain open. [Adobe file format specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/).

[Development record](DEVLOG.md#dev-step-605) · [Validation data](PSB_ROW_REUSE_605.json).
