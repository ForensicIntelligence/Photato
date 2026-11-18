<a id="dev-step-545"></a>

## 2026-11-17 — Compose flat tone stacks in one tile pass

Build 544's isolated 5,000 px first-dab probe spent 1,555 ms composing layers, 381 ms painting and 344 ms converting the updated display image. The 24 MP fixture uses a raster under two live Brightness/Contrast layers.

FlatToneRenderer.swift recognizes a full-canvas integer RGB raster with Normal Brightness/Contrast, Exposure and Invert layers above it. It applies the same stages in order and retains Float32 storage rounding after each stage. Opaque grid-aligned channels reuse exact transfer values. Transparent, fractional-alpha and older off-grid samples use the original blend and adjustment arithmetic. Masked, grouped, non-Normal and unsupported stacks keep their established compositor.

Surface.swift reads each aligned storage tile once and writes only the requested region, leaving the rest clear. Renderer.swift uses the same path for complete renders and regional work. RegionalRenderTests.swift compares both entry points with sequential rendering, including reusable damage, alpha, mapped tiles, signed zero, masked layers and legacy samples. Desktop and API composition share the renderer.

All 64 raw outputs match build 544 on both optimized architectures. The first run stopped at a Swift test-fixture type-check error. The corrected fixture passed all 390 selected methods in all three configurations, and both packaged binaries passed the offscreen workspace check.

At 5,000 px, Apple Silicon software composition went from 1628 to 124 ms. The paired AppKit first draws were 2372 and 896 ms. Physical editing cadence remains open. [Qualification](SOURCE_PUBLICATION_545.md).
