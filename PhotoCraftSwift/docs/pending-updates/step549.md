<a id="dev-step-549"></a>

## 2026-11-18 — Sample wide brush coverage in parallel

Build 548 still spends most of the paint phase on wide dabs. Running the existing round coverage sampler on a small batch of independent tiles improved the 5,000 px, two-dab Apple Silicon probe from 514 ms to 417 ms. The more general sampler routes the same geometry and per-tip effects through the workers. Its 5,000 px retained selected probe went from 392 ms to 353 ms on Apple Silicon. The translated Intel affine probe went from 44 ms to 50 ms and needs broader timing. Both prototypes matched the tested build 548 pixel digests.

BrushPainter.swift now prepares clipped tile weights in batches of at most 256 tiles, with up to four workers and 4 MiB of temporary pixel weights. Normal, selected and effected raster dabs share the same sampler. Workers only read immutable geometry and brush settings. The caller still admits tiles and applies weights in the original order, with the existing visit limits, cancellation checks and opacity calculations. Small dabs and ordinary hard round dabs stay on the serial path. Desktop and API calls keep sharing the existing stroke engine and need no request, action or document-format changes.

BrushDynamicsTests.swift adds a Float32 comparison against independent clipped serial strips. It covers a wide soft round brush and an angled Multiply brush with wet edges, noise and per-tip texture, through complete and retained painting. Info.plist advances the build to 549.

The first two native-probe attempts stopped at the restricted module cache and a Swift 6 captured-variable check. The repaired probes ran on both architectures. The first baseline-matrix attempt caught an argument-label typo in its standalone fixture. The first whole-source build attempt stopped at the restricted SwiftPM manifest cache. The repaired capture uses a separate module directory, and qualification uses the local native toolchain with its normal cache access. These failures are preserved under separate run paths.

All 146 raw comparison buffers match build 548. This includes 25 large round, hard, masked, textured, color-dynamics, transformed bitmap, Dual Brush, Eraser and symmetry outputs. All 398 selected methods passed in Debug and both optimized builds. Both packaged executables passed the offscreen workspace check. The saved 24-dab Photoshop comparison still has no exact cases.

At 5,000 px on Apple Silicon, the first held prefix took 244 ms in build 548 and 189 ms in build 549. Nine prefixes took 994 and 774 ms. The paired AppKit first draw measured 502 and 457 ms. The angled 1,100 px brush on a transformed layer was slower under Rosetta, from 47 to 51 ms. The same case took about 25 and 24 ms on Apple Silicon. Physical editing cadence remains open. [Qualification](SOURCE_PUBLICATION_549.md).
