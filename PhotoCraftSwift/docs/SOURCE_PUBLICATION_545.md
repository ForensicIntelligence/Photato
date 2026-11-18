# Source checkpoint 545

Native Swift 0.3.0, build 545, 17 November 2026. A full-size integer RGB raster with eligible unmasked Normal Brightness/Contrast, Exposure and Invert layers is evaluated one tile at a time. Opaque channel values on the source grid use a lookup table keyed to the original Float32 bit patterns. Other samples use sequential blend and adjustment arithmetic, preserving intermediate rounding and legacy input. Full and regional composition share this path. Other layer configurations continue through their existing rendering paths. Desktop and API callers use the same renderer.

The optimized builds reproduced all 64 full, regional, clipped and retained compositor outputs from build 544 byte for byte, including 8-bit and 16-bit sources, alpha, masked and non-Normal fallback controls, legacy off-grid samples, implicit tiles and mapped storage. Both optimized architectures agreed. The two new tests compare the compiled path with the sequential renderer. The first qualification stopped after the Swift type checker rejected a nested fixture expression. The second qualification passed all 390 selected tests in Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the universal validation ZIP passed the offscreen workspace check. The earlier unsupported PSD shape reference remains outside the selected tests.

## Regional software composition

Each row is the median of three first-dab runs on the 24 MP RGB8 fixture with two live Brightness/Contrast adjustments at 12.5% zoom. The probe measures painting and display conversion separately. At 5,000 px the Apple Silicon candidate spent 383 ms painting and 355 ms converting the display update.

| Runtime | Brush diameter | Build 544 composition | Build 545 composition |
| --- | --- | ---: | ---: |
| Apple Silicon | 64 px | 2.3 ms | 2.2 ms |
| Apple Silicon | 1,800 px | 316.0 ms | 24.4 ms |
| Apple Silicon | 2,500 px | 592.3 ms | 45.7 ms |
| Apple Silicon | 5,000 px | 1627.6 ms | 123.9 ms |
| Intel under Rosetta | 64 px | 3.5 ms | 3.7 ms |
| Intel under Rosetta | 1,800 px | 522.1 ms | 50.8 ms |
| Intel under Rosetta | 2,500 px | 967.5 ms | 80.5 ms |
| Intel under Rosetta | 5,000 px | 2693.0 ms | 235.1 ms |

## Hosted AppKit canvas

Two paired runs per build used 240 generated points at 120 Hz in the same 24 MP workspace with two live adjustment layers. Each run verified final native command pixels, one commit and Undo. The first-draw results include worker, scheduling, and AppKit draw time.

| Diameter | 544 first draw | 545 first draw | 544 draws during input | 545 draws during input |
| --- | ---: | ---: | --- | --- |
| 64 px | 22 ms | 22 ms | 119, 119 | 119, 119 |
| 1,800 px | 457 ms | 181 ms | 3, 3 | 23, 25 |
| 2,500 px | 853 ms | 316 ms | 1, 1 | 5, 5 |
| 5,000 px | 2372 ms | 896 ms | 0, 0 | 1, 2 |

Physical display cadence, physical tablet input, Photoshop pixel parity and other large layer configurations remain open.

[Development record](DEVLOG.md#dev-step-545) · [Validation evidence](FLAT_TONE_RENDERING_545.json) · [Frozen source](SOURCE_SNAPSHOT_545.json)
