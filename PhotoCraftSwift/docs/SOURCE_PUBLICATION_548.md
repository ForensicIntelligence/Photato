# Source checkpoint 548

Native Swift 0.3.0, build 548, 18 November 2026. Complete and retained raster Brush strokes prepare a fixed Normal ink once and write each tile using the existing source-over arithmetic. This covers unselected, unlocked raster targets with a constant foreground color. Post-dab texture in the retained renderer, grayscale targets, color dynamics, Eraser, other blend modes and selection coverage keep their established evaluation. The same paint code serves the desktop and the API.

All 120 complete and retained brush buffers match build 547 byte for byte on both optimized architectures. A separate buffer of 6,912 source-over samples agrees across all 27 blend modes. All 397 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The added regression check covers three depths and mapped storage, with a full-coverage mask as the reference. Both slices of the universal package passed the offscreen workspace check. The earlier unsupported PSD shape reference remains outside the selected tests.

## Repeated software brush preparation

Each row is the median of two trials using nine prefixes of a fixed 240-point stroke on a 24 MP raster. Both builds retain coverage. The final raster digests match in every comparison.

| Runtime | Diameter | Build 547 first prefix | Build 548 first prefix | Build 547 total | Build 548 total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Apple Silicon | 2,500 px | 127 ms | 79 ms | 789 ms | 479 ms |
| Apple Silicon | 5,000 px | 415 ms | 236 ms | 1689 ms | 970 ms |
| Intel under Rosetta | 2,500 px | 205 ms | 136 ms | 1224 ms | 791 ms |
| Intel under Rosetta | 5,000 px | 621 ms | 414 ms | 2524 ms | 1668 ms |

## Hosted AppKit canvas

Two runs per build used 240 generated samples in the 24 MP workspace at 12.5% zoom, with two live adjustments. Each run verified the final native command pixels, one commit and Undo. The last columns count draws linked to changed render inputs.

| Diameter | 547 first draw | 548 first draw | 547 changed-input draws | 548 changed-input draws |
| --- | ---: | ---: | --- | --- |
| 64 px | 22 ms | 22 ms | 117, 120 | 120, 120 |
| 1,800 px | 130 ms | 102 ms | 9, 9 | 9, 9 |
| 2,500 px | 232 ms | 181 ms | 6, 6 | 6, 7 |
| 5,000 px | 679 ms | 505 ms | 2, 2 | 3, 3 |

Physical display cadence, real tablet input and exact Photoshop Brush output remain open.

[Development record](DEVLOG.md#dev-step-548) · [Validation evidence](NORMAL_BRUSH_OUTPUT_548.json) · [Frozen source](SOURCE_SNAPSHOT_548.json)
