# Source checkpoint 536

Native Swift 0.3.0, build 536, 17 November 2026. Brush and Pencil now connect their last successful endpoint to a Shift-click on the same eligible raster target. The pointer shows the constraint badge and retains it through the captured gesture. The connection has one Undo entry. Starting or stopping Action recording preserves a valid endpoint. Undo, a changed document revision or an incompatible target prevents reuse. The Brush Action stores its points, and explicit HTTP samples replay through `paint.stroke` for Brush and `paint.tool` for Pencil. Pencil Action playback remains open. [Adobe Brush and Pencil workflow](https://helpx.adobe.com/photoshop/desktop/apply-painting-techniques/brushes-presets/paint-with-brush-or-pencil-tool.html).

All 171 focused and seven retained compositing methods pass in Debug, optimized Apple Silicon and optimized Intel under Rosetta. The main regression sends AppKit mouse events, checks the cursor and Undo, and compares the completed document with API replay for both tools and recorded Brush Action replay. The second checks wrong targets, cancellation, stale sessions and all sixteen modifier combinations. Both extracted executables pass the packaged offscreen workspace check.

## Photoshop Brush output

A 256 × 256 transparent RGB8 test document used a 13 px round white Brush at 100% zoom, opacity and flow. Photoshop exported a lossless PNG. A separate decoder checked the image and extracted alpha. The observed hard dabs matched between 0% and 10% smoothing. The normalized straight paths differed in 289 alpha samples by up to two levels. The native comparison uses the observed positions, nominal matching settings and an 80 ms command hold. Exact Photoshop engine samples and freehand device timing were unavailable.

| Sample | Photoshop nonzero alpha | Photato nonzero alpha | Differing samples in crop |
| --- | ---: | ---: | ---: |
| Soft dab, 10% | 347 | 120 | 347 |
| Hard dab, 0% | 193 | 156 | 98 |
| Hard dab, 10% | 193 | 156 | 98 |
| Straight path, 0% | 2,586 | 2,386 | 740 |
| Straight path, 10% | 2,586 | 2,386 | 740 |

Photato produced the same alpha bytes on both architectures and in both builds 535 and 536 for these explicit commands. Exact Brush coverage, factory presets, timed smoothing and stylus input remain open. The package declares macOS 14 as its minimum. Physical 60 fps, normal interactive bundle launch, actual macOS 14 and physical Intel were not exercised in this checkpoint.

[Development record](DEVLOG.md#dev-step-536) · [Validation evidence](BRUSH_REFERENCE_536.json) · [Frozen source](SOURCE_SNAPSHOT_536.json)
