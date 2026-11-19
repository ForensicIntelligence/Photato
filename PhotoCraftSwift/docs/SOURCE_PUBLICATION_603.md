# Source checkpoint 603

Native Swift 0.3.0, build 603, 19 November 2026. Large feathered vector masks reuse composited tiles wherever the filter inputs and layer samples are identical.

All 307,518,180 RGBA words in four complete renders matched build 602 on each architecture. The controls cover RGB8, RGB16, and RGB32, both mask polarities, 2 px and 110.25 px Feather, a clipped raster stack inside a group, and altered raster and pixel mask tiles.

The 300,000 × 75 control went from 39 rendered patches to 15. The RGB16 wide-Feather control went from 156 to 111.

The full 300,000 × 300,000 rounded-mask control completed in 6.47 s on Apple Silicon and 13.10 s under Rosetta, with 28 rendered patches. The maximum-size ellipse completed in 64.16 s on Apple Silicon and 113.97 s under Rosetta, with 9,804 rendered patches. The rounded mask at 110.25 px Feather completed in 110.45 s on Apple Silicon and 171.10 s under Rosetta, with 5,632 rendered patches. Across the three composites, all 745,024 RGBA words in 26 sampled regions matched build 602 viewports on each architecture. These are single runs on the same Mac. [Adobe PSB dimensions](https://helpx.adobe.com/photoshop/desktop/save-and-export/export-files-to-different-formats/image-file-formats-supported-in-photoshop.html).

All 922 selected tests passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both extracted universal app slices passed signature and offscreen launch checks. The package declares macOS 14 as its minimum.

The installed Photoshop app returned an AppleEvent timeout on a read-only document count. Fresh Photoshop samples, practical wide Feather on maximum-size ellipses, physical Intel and macOS 14 runtime, large-file export at the maximum dimensions and full Photoshop byte parity remain open.

[Development record](DEVLOG.md#dev-step-603) · [Validation data](SOLID_VECTOR_COMPOSITE_603.json).
