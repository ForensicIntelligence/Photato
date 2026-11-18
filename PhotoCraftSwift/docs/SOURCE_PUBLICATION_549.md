# Source checkpoint 549

Native Swift 0.3.0, build 549, 18 November 2026. Complete and retained raster Brush strokes sample eligible wide-dab coverage across up to four workers. This includes round soft brushes, selected targets, bitmap and angled tips, color dynamics, and per-tip effects. The stroke deposits weights in their previous order. Each batch caps its temporary weights at 4 MiB. The same paint code serves the desktop and the API.

All 146 pixel buffers match build 548 byte for byte on both optimized architectures. They include 25 large-stroke outputs and the earlier Brush and blend cases. The new Float32 regression compares complete and retained strokes against serial clipped strips, using a soft round brush and an angled Multiply brush with texture, noise and wet edges. All 398 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the universal package passed the offscreen workspace check. The earlier unsupported PSD shape reference remains outside the selected tests.

## Repeated software brush preparation

Each row is the median of two trials using nine prefixes of a fixed 240-point stroke on a 24 MP raster. Both builds retain coverage. The final raster digests match in every comparison.

| Runtime | Diameter | Build 548 first prefix | Build 549 first prefix | Build 548 total | Build 549 total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Apple Silicon | 2,500 px | 79 ms | 62 ms | 491 ms | 374 ms |
| Apple Silicon | 5,000 px | 244 ms | 189 ms | 994 ms | 774 ms |
| Intel under Rosetta | 2,500 px | 133 ms | 117 ms | 830 ms | 701 ms |
| Intel under Rosetta | 5,000 px | 424 ms | 353 ms | 1721 ms | 1437 ms |

## Brush settings and transformed layers

The following native paint-only timings use four measurements per build. The final pixels match for every case.

| Brush | Apple Silicon 548 | Apple Silicon 549 | Rosetta 548 | Rosetta 549 |
| --- | ---: | ---: | ---: | ---: |
| 64 px soft | 0.08 ms | 0.08 ms | 0.13 ms | 0.13 ms |
| 5,000 px with selection | 408.50 ms | 368.54 ms | 592.20 ms | 561.51 ms |
| 2,500 px with Color Dynamics | 167.10 ms | 150.24 ms | 253.79 ms | 227.09 ms |
| 1,100 px angled, layer transformed | 25.10 ms | 24.24 ms | 46.99 ms | 50.84 ms |
| 900 px Wet Edges and Noise | 32.01 ms | 26.98 ms | 61.49 ms | 52.18 ms |

The angled 1,100 px brush on a transformed layer was slower under Rosetta, from 47 to 51 ms. The same case took about 25 and 24 ms on Apple Silicon.

## Hosted AppKit canvas

Two runs per build used 240 generated samples in the 24 MP workspace at 12.5% zoom, with two live adjustments. Each run verified the final native command pixels, one commit and Undo. The last columns count draws linked to changed render inputs.

| Diameter | 548 first draw | 549 first draw | 548 changed-input draws | 549 changed-input draws |
| --- | ---: | ---: | --- | --- |
| 64 px | 22 ms | 22 ms | 117, 119 | 118, 118 |
| 1,800 px | 104 ms | 94 ms | 9, 9 | 9, 9 |
| 2,500 px | 183 ms | 166 ms | 6, 7 | 7, 7 |
| 5,000 px | 502 ms | 457 ms | 3, 3 | 3, 3 |

The 24 saved Adobe Photoshop 2026 round-brush cases still differ. Build 549 reproduces the native alpha recorded at checkpoint 537 on both architectures. The controlled AppKit timing uses synthetic input. Physical display cadence and real tablet input remain open.

[Development record](DEVLOG.md#dev-step-549) · [Validation evidence](PARALLEL_BRUSH_COVERAGE_549.json) · [Frozen source](SOURCE_SNAPSHOT_549.json)
