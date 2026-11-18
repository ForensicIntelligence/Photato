<a id="dev-step-544"></a>

## 2026-11-17 — Prepare wide brush dabs once and start the first preview sooner

In the build 543 AppKit fixture, the first draw took 501 ms with a 1,800 px Brush, 966 ms with a 2,500 px Brush and 2,669 ms with a 5,000 px Brush. The two widest tips first started preparing after about 20 ms, with two input samples already queued. Most of the measured latency was in the preview worker.

BrushPainter.swift prepares rotation, projection, centre alignment, bitmap scale and falloff once per dab. An unrotated round tip on an untransformed raster uses an exact distance loop and can fill or skip tiles wholly inside or outside coverage. A half-pixel margin preserves scalar evaluation at the boundaries. PaintToolPainter.swift reuses the prepared sampler for both primary and dual tips. BrushEditing.swift submits the ordinary first raster preview from the input event for complete and retained strokes when the canvas is ready. The same raster kernels serve the desktop and API. Current formats, brush settings and release-tail rules still apply.

BrushDynamicsTests.swift compares the tile path with scalar weights at clipped edges, fractional positions and soft and hard settings. CanvasFrameDiagnosticsTests.swift checks the first submission, final preview, exact command commit and single Undo for a wide tip.

All 64 raw output cases match build 543 byte for byte on both optimized architectures. All 388 selected tests passed in Debug and both optimized builds. Both slices of the universal archive passed the offscreen workspace check.

In repeated 24 MP AppKit runs, median first draw changed from 473 to 483 ms at 1,800 px, from 882 to 859 ms at 2,500 px and from 2442 to 2343 ms at 5,000 px. The 2,500 and 5,000 px first previews start from the initial pointer sample. The physical 60 fps target remains open. [Qualification](SOURCE_PUBLICATION_544.md).
