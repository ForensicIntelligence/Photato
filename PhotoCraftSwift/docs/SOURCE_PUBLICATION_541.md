# Source checkpoint 541

Native Swift 0.3.0, build 541, 17 November 2026. The retained Brush writes changed tiles from the original surface and reuses the original tile when a provisional tail moves away. Common flat adjustment layers and ordinary translated raster layers at RGB8 and RGB16 use the same tile writer. The compositor advances over a temporary backdrop one tile at a time. Existing color formulas, selection and mask behavior, command schemas, stored document format and Actions format are retained.

All 266 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. Seven selected compositing methods cover 20 independent Photoshop exports. The two new methods cover partial tiles, a mapped source, signed zeros, a provisional brush tail and the exact completed stroke. The optimized modules reproduce all 32 Brush buffers and all 144 composite buffers from build 540 on each architecture. The same 18 Gradient Map buffers differ between architectures in both builds. The differences affect 155 RGB words, including repeated regional captures, by at most four Float32 steps. Alpha matches. A separate probe of build 540 found architecture differences in 70 of 4,097 Perceptual ramp positions and 17 Linear positions. Both executables in the universal ZIP passed the offscreen workspace check.

## Hosted Brush timing

The optimized AppKit workspace received 240 generated points at a target 120 Hz on a 24 MP raster with two live adjustment layers, 12.5% zoom and Brush smoothing disabled. Each build and diameter ran once, with alternating build order. The eight runs match the full native stroke exactly and pass single commit and Undo.

| Diameter | Build 540 first draw | Build 541 first draw | Draws during input in 540 | Draws during input in 541 |
| --- | ---: | ---: | ---: | ---: |
| 64 px | 21 ms | 22 ms | 119 | 119 |
| 1,800 px | 802 ms | 489 ms | 1 | 2 |
| 2,500 px | 1415 ms | 911 ms | 1 | 1 |
| 5,000 px | 3606 ms | 2500 ms | 0 | 0 |

The timing covers the hosted input queue and AppKit draw callbacks. Physical display and stylus measurements are open. Brush sampling parity, dense linear Float32 rendering and the remaining large-tip preparation costs are open. The same renderer serves desktop and API requests. Current Photoshop defaults for smoothing and spacing remain the workflow reference. [Adobe painting and cloning performance](https://helpx.adobe.com/photoshop/desktop/apply-painting-techniques/brushes-presets/optimize-painting-and-cloning-using-brush-settings.html).

[Development record](DEVLOG.md#dev-step-541) · [Validation evidence](TILE_COMPOSITING_541.json) · [Frozen source](SOURCE_SNAPSHOT_541.json)
