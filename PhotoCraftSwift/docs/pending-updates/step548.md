<a id="dev-step-548"></a>

## 2026-11-18 — Speed up Normal brush tile output

Build 547 saves repeated wide-stroke work. Its first 5,000 px software preview took 476 ms in the prior timing comparison. An isolated prototype on the same renderer reduced a dense retained preview from 472 to 244 ms by preparing the ink once and omitting coordinate lookup in the tile writer for eligible Normal strokes. A separate prototype wrote a tile immediately after coverage generation. Its wider stroke timings varied, and the tested two-dab case was slower than the prepared-ink path alone.

BrushPainter.swift now prepares Normal output for raster strokes with a fixed ink color, no selection and no transparency lock. The complete and retained painters still use their existing coverage. The two routes share the source-over calculation in Color.swift. The retained path keeps the existing evaluation for post-dab texture. Selections, color dynamics, Eraser, grayscale targets and other modes keep their established pixel rules.

BrushDynamicsTests.swift compares the complete and retained paths with a full-coverage mask through all three depths and mapped storage. It includes signed zeros, hidden color, partially transparent pixels and post-dab texture. Desktop and API operations share the paint code.

All 120 brush captures and the all-mode blend buffer match build 547 exactly. All 397 selected methods passed in Debug and both optimized builds, including the original blend reference test. Both packaged executables passed the offscreen workspace check.

At 5,000 px on Apple Silicon, the first held prefix took 415 ms in build 547 and 236 ms in build 548. Nine prefixes took 1689 and 970 ms. The paired AppKit first draw measured 679 and 505 ms. Physical editing cadence remains open. [Qualification](SOURCE_PUBLICATION_548.md).
