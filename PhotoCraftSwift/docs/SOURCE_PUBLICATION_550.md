# Source checkpoint 550

Native Swift 0.3.0, build 550, 18 November 2026. Eligible large flat tone stacks and regional display conversion run in four independent bands. The compositor reads immutable samples and joins Float32 tiles. The display packer writes disjoint row ranges into one borrowed buffer. The shared renderer retains the existing calculations for working pixels, display bytes, and exports. The desktop and API use the same engine.

All 192 composite and display buffers match build 549 on each optimized architecture. The eight existing differences between architectures are confined to the saved ColorSync display cases. All 400 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. Two new regressions cover unaligned band boundaries, mapped storage, HDR display encoding and immutable previous frames. Both packaged executables passed the offscreen workspace check. The unsupported PSD shape reference remains outside the selected tests.

## Software phases

Each row shows the medians in milliseconds from three trials per diameter, first from build 549 and then build 550. The test uses independently timed paint, composition and display preparation on a 24 MP raster at 12.5% zoom with two tone adjustments.

| Runtime | Diameter | Paint | Composite | Display preparation |
| --- | ---: | ---: | ---: | ---: |
| Apple Silicon | 64 px | 0.5 → 0.5 | 2.1 → 2.1 | 0.6 → 0.6 |
| Apple Silicon | 1,800 px | 32.9 → 31.6 | 25.1 → 9.5 | 23.1 → 11.1 |
| Apple Silicon | 2,500 px | 58.3 → 59.8 | 45.3 → 16.0 | 39.8 → 17.4 |
| Apple Silicon | 5,000 px | 189.3 → 192.7 | 122.3 → 42.8 | 100.5 → 39.8 |
| Intel under Rosetta | 64 px | 0.7 → 0.7 | 3.5 → 3.7 | 0.6 → 0.6 |
| Intel under Rosetta | 1,800 px | 61.0 → 62.2 | 50.0 → 17.6 | 33.9 → 14.9 |
| Intel under Rosetta | 2,500 px | 111.2 → 104.1 | 84.2 → 27.5 | 56.0 → 24.4 |
| Intel under Rosetta | 5,000 px | 349.6 → 336.4 | 234.8 → 73.6 | 147.4 → 60.4 |

## Hosted AppKit canvas

The hosted test uses 240 generated input points and checks the final native command pixels, one history entry and Undo. Each diameter has two runs per build. The last columns count draws associated with changed render inputs.

| Diameter | 549 first draw | 550 first draw | 549 changed-input draws | 550 changed-input draws |
| --- | ---: | ---: | --- | --- |
| 64 px | 22 ms | 22 ms | 117, 119 | 117, 119 |
| 1,800 px | 93 ms | 63 ms | 9, 9 | 9, 9 |
| 2,500 px | 165 ms | 108 ms | 7, 7 | 7, 7 |
| 5,000 px | 460 ms | 304 ms | 3, 3 | 3, 3 |

Physical display cadence, real tablet input and exact Photoshop Brush samples remain open.

[Development record](DEVLOG.md#dev-step-550) · [Validation evidence](RASTER_PIPELINE_550.json) · [Frozen source](SOURCE_SNAPSHOT_550.json)
