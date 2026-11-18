# Source checkpoint 551

Native Swift 0.3.0, build 551, 18 November 2026. Wide brush updates prepare independent output tiles in four jobs and apply them in the original order. The complete stroke and retained preview share the existing blend and storage calculations. The retained preview can restore original mapped tiles and implicit fill when a smoothing tail moves. The desktop and API use the same engine.

All 338 brush, composite and display buffers match build 550 on each optimized architecture. The eight existing differences between architectures are confined to ColorSync display cases. All 401 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The new regression compares serial and parallel restoration across two tile batches, including clipped, mapped and absent tiles. Both packaged executables passed the offscreen workspace check. The unsupported PSD shape reference remains outside the selected tests.

## Software phases

Each row shows the medians in milliseconds from three trials per diameter, first from build 550 and then build 551. The test uses independently timed paint, composition and display preparation on a 24 MP raster at 12.5% zoom with two tone adjustments.

| Runtime | Diameter | Paint | Composite | Display preparation |
| --- | ---: | ---: | ---: | ---: |
| Apple Silicon | 64 px | 0.6 → 0.6 | 2.6 → 2.6 | 0.7 → 0.6 |
| Apple Silicon | 1,800 px | 37.6 → 14.5 | 10.2 → 9.9 | 11.8 → 11.8 |
| Apple Silicon | 2,500 px | 65.2 → 26.6 | 16.8 → 17.4 | 17.9 → 19.0 |
| Apple Silicon | 5,000 px | 215.9 → 83.0 | 45.5 → 43.2 | 43.4 → 43.1 |
| Intel under Rosetta | 64 px | 0.8 → 0.7 | 3.7 → 3.6 | 0.7 → 0.6 |
| Intel under Rosetta | 1,800 px | 73.9 → 24.1 | 17.0 → 16.4 | 15.6 → 14.2 |
| Intel under Rosetta | 2,500 px | 132.7 → 42.6 | 26.4 → 25.4 | 26.0 → 23.2 |
| Intel under Rosetta | 5,000 px | 389.3 → 134.3 | 77.0 → 79.2 | 59.3 → 58.1 |

## Brush settings and storage

The paint-only cases used four timed samples per build. All final pixels match.

| Runtime | Case | Build 550 ms | Build 551 ms |
| --- | --- | ---: | ---: |
| Apple Silicon | 64 px soft control | 0.15 | 0.14 |
| Apple Silicon | 5,000 px with selection | 384.62 | 126.51 |
| Apple Silicon | 2,500 px Color Dynamics | 161.43 | 50.10 |
| Apple Silicon | 5,000 px two-dab preview | 468.70 | 177.00 |
| Apple Silicon | 1,800 px linear Float32 | 96.38 | 32.10 |
| Apple Silicon | 1,100 px angled, transformed layer | 24.02 | 11.30 |
| Apple Silicon | 900 px Wet Edges and Noise | 27.04 | 10.06 |
| Intel under Rosetta | 64 px soft control | 0.15 | 0.17 |
| Intel under Rosetta | 5,000 px with selection | 572.34 | 195.07 |
| Intel under Rosetta | 2,500 px Color Dynamics | 247.44 | 82.42 |
| Intel under Rosetta | 5,000 px two-dab preview | 812.41 | 307.13 |
| Intel under Rosetta | 1,800 px linear Float32 | 227.08 | 62.52 |
| Intel under Rosetta | 1,100 px angled, transformed layer | 56.26 | 25.51 |
| Intel under Rosetta | 900 px Wet Edges and Noise | 58.98 | 19.21 |

## Hosted AppKit canvas

The hosted test uses 240 generated input points and checks the final native command pixels, one history entry and Undo. Each diameter has two runs per build. The last columns count draws associated with changed render inputs.

| Diameter | 550 first draw | 551 first draw | 550 changed-input draws | 551 changed-input draws |
| --- | ---: | ---: | --- | --- |
| 64 px | 22 ms | 22 ms | 116, 117 | 118, 120 |
| 1,800 px | 64 ms | 43 ms | 9, 9 | 10, 10 |
| 2,500 px | 111 ms | 71 ms | 7, 7 | 7, 7 |
| 5,000 px | 315 ms | 181 ms | 3, 3 | 4, 4 |

Physical display cadence, real tablet input and exact Photoshop Brush samples remain open.

[Development record](DEVLOG.md#dev-step-551) · [Validation evidence](BRUSH_TILE_OUTPUT_551.json) · [Frozen source](SOURCE_SNAPSHOT_551.json)
