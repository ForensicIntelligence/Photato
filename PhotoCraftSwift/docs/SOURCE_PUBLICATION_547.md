# Source checkpoint 547

Native Swift 0.3.0, build 547, 18 November 2026. Ordinary rasters can retain coverage from Brush gestures up to 5,000 px. When a first dab settles, the renderer reuses its provisional coverage only if every raster input bit agrees. The preview keeps the previous raster if the new samples deposit nothing and leave the tail unchanged. Wide strokes use the complete banded renderer if projected or actual retained coverage exceeds 128 MiB. Dual tips, symmetry and auxiliary paths keep their existing routing. Release and fallback preserve the original brush command, every sample, Actions and Undo. The native command and API contracts keep their existing formats.

All 60 raw outputs from the optimized retained path match build 546's complete renderer on both architectures. The sample set covers held prefixes, release, color dynamics, texture, protection, select-mask coverage, erasure and input direction at all three depths. The initial reference fixture was rejected because its rectangle disagreed with its selection mask. The corrected fixture derives the rectangle from that mask. All 395 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the universal package passed the offscreen workspace check. The earlier unsupported PSD shape reference remains outside the selected tests.

## Repeated software brush preparation

Each row is the median of two trials using nine prefixes of a fixed 240-point stroke on a 24 MP raster. The second prefix adds one pointer sample that settles the previous first dab. The 5,000 px first prefix on Apple Silicon increased from 398 to 476 ms. The final raster digests match in every comparison.

| Runtime | Diameter | Build 546 total | Build 547 total | Build 546 second prefix | Build 547 second prefix |
| --- | ---: | ---: | ---: | ---: | ---: |
| Apple Silicon | 2,500 px | 1997 ms | 895 ms | 134.6 ms | 0.020 ms |
| Apple Silicon | 5,000 px | 4749 ms | 1872 ms | 394.8 ms | 0.012 ms |
| Intel under Rosetta | 2,500 px | 2862 ms | 1236 ms | 198.6 ms | 0.018 ms |
| Intel under Rosetta | 5,000 px | 7116 ms | 2660 ms | 599.9 ms | 0.017 ms |

## Hosted AppKit canvas

Two runs per build used 240 generated point samples in the 24 MP workspace at 12.5% zoom with two live adjustments. Each run verified the final pixels, one commit and Undo. The last columns count draws linked to a render whose input changed. The evidence also records every draw, including repeats.

| Diameter | 546 first draw | 547 first draw | 546 changed-input draws | 547 changed-input draws |
| --- | ---: | ---: | --- | --- |
| 64 px | 21 ms | 22 ms | 118, 118 | 119, 119 |
| 1,800 px | 127 ms | 127 ms | 9, 9 | 9, 9 |
| 2,500 px | 217 ms | 227 ms | 5, 5 | 6, 6 |
| 5,000 px | 621 ms | 654 ms | 2, 2 | 2, 2 |

The second 5,000 px changed-input draw arrived 1358 ms after the first input, down from 1413 ms. Physical display cadence, real tablet input and exact Photoshop Brush output remain open.

[Development record](DEVLOG.md#dev-step-547) · [Validation evidence](RETAINED_WIDE_BRUSH_547.json) · [Frozen source](SOURCE_SNAPSHOT_547.json)
