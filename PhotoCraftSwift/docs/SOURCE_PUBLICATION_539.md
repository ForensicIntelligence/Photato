# Source checkpoint 539

Native Swift 0.3.0, build 539, 17 November 2026. Profiling the 5,000 px Brush showed repeated tile lookups during coverage accumulation and surface writes. The renderer now processes each dab's coverage by tile and publishes each finished Brush tile with one storage write. It reuses unshared coverage from completed passes. The formulas for brush coverage, blending and stored sample quantization stay the same.

All 198 focused and seven retained compositing methods passed in Debug, optimized Apple Silicon and Intel under Rosetta. Both executables from the universal ZIP passed the offscreen workspace check. The new partial-tile test compares the bulk writer with individual setters for owned and mapped RGB8, RGB16, encoded Float32 and linear Float32 pixels. An independent comparison found that all 32 tested stored RGBA buffers match build 538 within each architecture. Six linear Float32 buffers differed between architectures in both builds. The 24 earlier small-dab comparisons also match build 538 on both architectures.

## Full-size brush rendering

The comparison uses the same Mac, optimized engines, a 5,000 px brush and a 5,408 × 5,408 RGB8 surface. Each row is the median of three render-only trials after an initial warmup. For each scenario the complete 116,985,856 output bytes produced the same digest across both builds and architectures.

| Dab | Runtime | Build 538 | Build 539 | Time reduction |
| --- | --- | ---: | ---: | ---: |
| Color dynamics | Apple Silicon | 1.99 s | 0.52 s | 73.8% |
| Soft | Apple Silicon | 2.81 s | 0.54 s | 80.9% |
| Color dynamics | Intel under Rosetta | 3.61 s | 0.90 s | 75.1% |
| Soft | Intel under Rosetta | 5.99 s | 0.94 s | 84.4% |

These measurements cover complete software rasterization. The live input, document compositing and physical display cadence of large strokes still need measurement. Photoshop output equality and current live Pencil limits remain open.

[Development record](DEVLOG.md#dev-step-539) · [Validation evidence](BRUSH_TILE_PERFORMANCE_539.json) · [Frozen source](SOURCE_SNAPSHOT_539.json)
