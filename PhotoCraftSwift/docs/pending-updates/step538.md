<a id="dev-step-538"></a>

## 2026-11-17 — Support 5,000 px primary brush diameters

The ordinary Brush and Adjustment Brush were limited to 2,048 px. Adobe lists a 5,000 px maximum for both, and the owned Photoshop check in step 455 observed an Eraser set to 5,000 px. The Mac was locked during the first attempt to repeat the controls in Photoshop 2026. [Adobe Brush and Adjustment Brush limits](https://community.adobe.com/questions-712/brush-size-limits-at-5000px-1181701).

The primary brush diameter range now reaches 5,000 px in the shared paint settings, typed API, and native controls. The Brush Tip and Eraser sliders use a logarithmic scale to keep small sizes easy to adjust. Brush Settings adds direct size entry alongside its slider. The right bracket can reach 5,000 px. Defining a sampled tip now retains its actual dimensions up to the existing 2,500 px bitmap limit. Retouch brushes, secondary tips and the pre-settings stroke format keep their original diameter rules.

BrushPainter.swift divides strokes over 2,048 px into disjoint, tile-aligned coverage bands. The banded path applies the same deposition, texture, color, and blend calculations. A selection reduces the raster extent through its layer transform. One stroke-wide work limit still applies, with cancellation checks inside wide dabs. The renderer publishes the prepared surface after all bands succeed. Ordinary brushes up to 2,048 px retain their existing preview routing. Wider brushes use complete preparation for preview and commit.

BrushDynamicsTests.swift covers a full-size color-dynamics dab, band boundaries, transformed and clipped coverage against the existing unbanded renderer, the old legacy diameter limit, and an atomic work-limit refusal. BrushWorkflowTests.swift exercises the keyboard size action, held preview, commit, recorded Action, Undo, typed HTTP configuration and explicit stroke, and a newly defined wide sampled brush. BrushPresetCodecTests.swift covers a 5,000 px native and computed ABR preset round trip.

All 197 focused tests and seven retained compositing tests pass in Debug, optimized Apple Silicon and Intel under Rosetta. Both extracted universal executables passed the offscreen workspace check. The two architecture slices produced the same full RGBA digest for the 5,000 px dab and agreed on all 24 smaller, earlier Brush comparisons. The complete large dab took 2.11 seconds on Apple Silicon in the standalone renderer. Wide-tip responsiveness and physical display timing remain open. [Qualification](SOURCE_PUBLICATION_538.md).
