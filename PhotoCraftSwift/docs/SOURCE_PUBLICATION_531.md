# Source checkpoint 531

Native Swift 0.3.0, build 531, 17 November 2026. Ordinary tile maps now find potential changes while walking the existing dictionaries. If two entries share immutable sample storage, the damage scan can skip them. Independent storage, insertions and removals still go through exact comparison. Persistent radix trees and unrelated mapped bases retain their existing difference paths.

The two new checks cover equal sample values with separate storage, shared tiles, inserts, removals, and transparent Float32 signed zero at a partial tile edge. All 90 selected tests pass on Debug, optimized Apple Silicon and translated Intel. The tests include Undo/Redo and full-versus-regional rendering, packed and reduced previews, native archive samples and paged raster ownership. Both optimized runs execute the same method list in the same order.

## Timings and exact samples

The native benchmark uses an owned 6000 × 4000 raster with two contrast adjustments and 240 ordinary brush samples. Both builds are tested twice in 530, 531, 531, 530 order. The tile-damage case independently checks the exact bounds for 200 one-pixel changes on the same dense raster. A separate hosted AppKit run uses the same dimensions, a 12.5% view and a generated 120 Hz input stream. The table summarizes each metric across the two runs per build.

| Stage | Build 530 median | Build 531 median | Build 530 p95 | Build 531 p95 |
| --- | ---: | ---: | ---: | ---: |
| Single-tile damage scan | 1.42 ms | 0.30 ms | 1.58 ms | 0.33 ms |
| Stroke batch through composite | 7.01 ms | 4.93 ms | 9.06 ms | 6.85 ms |
| Hosted preparation through ready preview | 9.33 ms | 6.33 ms | 14.79 ms | 12.26 ms |
| Hosted input through AppKit draw | 20.73 ms | 12.64 ms | 28.02 ms | 23.55 ms |

The individual hosted input-to-draw p95 readings were 26.27, 29.76 ms in build 530 and 27.11, 19.99 ms in build 531.

All four standalone runs have identical SHA-256 digests for full-size display bytes, reduced display bytes, and all Float32 composite sample bytes. Each run also checks the result against a complete native stroke and full renderer. The hosted runs preserve every input sample and independently verify their final previews against the complete native command.

The universal candidate passes the macOS 14 minimum-version, architecture, resources, signature and extracted archive checks. The window tests run from XCTest. Physical pointer and monitor presentation, sandboxed packaged launch, actual macOS 14 and physical Intel, and Photoshop output parity remain open. The change keeps the existing brush math, archive, shortcuts and both API contracts. All earlier parity gaps remain tracked.

[Development record](DEVLOG.md#dev-step-531) · [Measurements](LAYERED_BRUSH_DAMAGE_531.json) · [Frozen source](SOURCE_SNAPSHOT_531.json)
