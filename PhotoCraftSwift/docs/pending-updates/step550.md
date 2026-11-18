<a id="dev-step-550"></a>

## 2026-11-18 — Parallelize large raster composition and display packing

A new phase probe used the build 549 retained brush on a 24 MP raster with two live tone adjustments. The 5,000 px first update on Apple Silicon spent 232 ms painting, 121 ms compositing and 102 ms preparing the display. A prototype divided the render region along storage tile rows. Its first invocation forced the flat compositor on the 64 px control and stopped because that control still uses the general renderer. A separate run preserved the normal fallback. The two optimized builds matched all tested composite, full display and reduced display digests, and the combined 5,000 px compositing and display stages took 88 ms on Apple Silicon.

Surface.swift adds four independent bands for large raster work. Eligible flat tone stacks build Float32 tiles per band and join the tiles in document coordinates. The core serial public method remains available. The existing display packer writes into separate row ranges in one borrowed buffer, after checking its bounds. The caller waits for all rows and can discard the result on cancellation. Small regions use the existing serial loops. FlatToneRenderer.swift calls the independent-band compositor for eligible stacks. Managed color conversion and the canvas reduction filter continue to use their current methods. The shared render path covers the desktop and the API, with the same operations and document format.

RegionalRenderTests.swift compares an unaligned 16-bit source and mapped tiles against the sequential compositor. CanvasRasterPreviewTests.swift compares a large unaligned RGB32 regional display with a full redraw, including mapped HDR, retained pixels outside the update, and reduced display bytes. Info.plist advances the build to 550.

All 192 raw buffers match build 549 on each architecture. The eight existing ColorSync display differences between architectures persist with the same bytes. All 400 selected tests pass on three configurations, and both packaged runtimes pass offscreen checks.

At 5,000 px on Apple Silicon, the composition and display stages together took 223 ms in build 549 and 83 ms in build 550. The first offscreen AppKit draw took 460 and 304 ms. Physical editing cadence and Photoshop Brush samples remain open. [Qualification](SOURCE_PUBLICATION_550.md).
