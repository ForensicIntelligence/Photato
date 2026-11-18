# Source checkpoint 546

Native Swift 0.3.0, build 546, 17 November 2026. A regional canvas update for a document without an explicit working ICC profile packs straight-alpha sRGB8 directly from its intersecting storage tiles. The copy retains pixels outside the damaged region. A custom working profile uses the existing color-managed conversion. Whole-pixel zoom reductions accumulate integer alpha and premultiplied channel sums, then round once using the same output rule. The weighted filter remains in use for fractional boxes and boxes larger than the accumulator bound. Working raster samples, document formats and API contracts stay compatible.

All 80 checked outputs match build 545 byte for byte on each optimized architecture. The captures include full and regional preview bytes, several zooms, erased and translucent pixels, partial and mapped tiles, HDR, custom profiles and RGBA8 exports. The two ColorSync buffers with existing architecture differences retain the same two red bytes that differ by one level. Alpha matches. The baseline and candidate match across the other 78 captures. All 392 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the universal validation ZIP passed the offscreen workspace check. The earlier unsupported PSD shape reference remains outside the selected tests.

## Display conversion

Each row is the median of three first-dab runs on the 24 MP RGB8 fixture with two live adjustments at 12.5% zoom. The conversion timer includes packing and updating the zoomed-out image. At 5,000 px, the Apple Silicon candidate spent 384 ms painting and 127 ms on regional composition.

| Runtime | Brush diameter | Build 545 conversion | Build 546 conversion |
| --- | ---: | ---: | ---: |
| Apple Silicon | 64 px | 0.8 ms | 0.5 ms |
| Apple Silicon | 1,800 px | 72.7 ms | 23.3 ms |
| Apple Silicon | 2,500 px | 134.1 ms | 40.9 ms |
| Apple Silicon | 5,000 px | 357.4 ms | 103.3 ms |
| Intel under Rosetta | 64 px | 1.0 ms | 0.6 ms |
| Intel under Rosetta | 1,800 px | 125.4 ms | 31.7 ms |
| Intel under Rosetta | 2,500 px | 233.2 ms | 57.4 ms |
| Intel under Rosetta | 5,000 px | 628.3 ms | 149.8 ms |

## Hosted AppKit canvas

Two runs per build used 240 generated points at 120 Hz in the same 24 MP workspace, with order reversed for the second run. Each run verified final command pixels, one commit and Undo.

| Diameter | 545 first draw | 546 first draw | 545 draws during input | 546 draws during input |
| --- | ---: | ---: | --- | --- |
| 64 px | 21 ms | 23 ms | 119, 120 | 119, 119 |
| 1,800 px | 178 ms | 130 ms | 24, 24 | 50, 50 |
| 2,500 px | 319 ms | 224 ms | 5, 5 | 6, 6 |
| 5,000 px | 913 ms | 647 ms | 1, 1 | 2, 2 |

Physical display cadence and physical tablet input remain unmeasured. Large-tip preparation, Photoshop pixel comparisons and physical platform validation remain open.

[Development record](DEVLOG.md#dev-step-546) · [Validation evidence](CANVAS_CONVERSION_546.json) · [Frozen source](SOURCE_SNAPSHOT_546.json)
