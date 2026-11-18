<a id="dev-step-551"></a>

## 2026-11-18 — Parallelize brush tile output

An isolated build 550 probe split the retained paint phase into coverage and output. An Apple Silicon 5,000 px dense first dab spent 32 ms on coverage and 170 ms writing the raster. A similarly sized dab with a selection spent 30 ms on coverage and 332 ms writing. The Linear Float32 case also spent most of its time in the writer.

Surface.swift now prepares unique brush output tiles from immutable inputs in up to four jobs, with batches of at most 256 tiles. The new jobs use the existing pixel blend and storage conversions. The caller joins the jobs, installs their results and updates opacity evidence. BrushPainter.swift passes immutable coverage and any per-tip colors through this shared writer in the complete and retained paths. The small update remains serial. The retained path restores the original mapped tile or removes the allocated preview tile if an abandoned smoothing tail left no replacement coverage. The desktop and API still use the shared paint code and existing document, action and command formats.

BrushDynamicsTests.swift compares serial and parallel output across two batches, with RGB8 and linear Float32 storage, clipped edges, mapped originals, absent tiles and hidden color. Info.plist advances the build to 551.

All 338 raw buffers match build 550 on each architecture. The eight existing ColorSync display differences between architectures persist with the same bytes. All 401 selected tests pass on three configurations, and both packaged runtimes pass offscreen checks.

At 5,000 px on Apple Silicon, the paint phase took 216 ms in build 550 and 83 ms in build 551. The first offscreen AppKit draw took 315 and 181 ms. Physical editing cadence and Photoshop Brush samples remain open. [Qualification](SOURCE_PUBLICATION_551.md).
