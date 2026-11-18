# Source checkpoint 554

Native Swift 0.3.0, build 554, 18 November 2026. The four factory Round presets now change smoothly from soft feathering to an opaque core with a narrow edge. The aligned nonzero-hardness samples improved from a worst alpha difference of 161 to 12 of 255 levels. The changes apply to Hard Round, Soft Round and their pressure variants through the shared Brush renderer. Antialiasing and the existing tool settings still apply. [Adobe Brush and Pencil guide](https://helpx.adobe.com/photoshop/desktop/apply-painting-techniques/brushes-presets/paint-with-brush-or-pencil-tool.html).

Across the 18 center-aligned RGB8 dabs at nonzero hardness, the worst alpha difference fell from 161 to 12 of 255 levels. Every tested nonzero-hardness dab had a lower total absolute error. The two independent 13 px hard dabs were within 2 levels. All six zero-hardness renders match build 553 byte for byte. The same Swift probe produced identical alpha on Apple Silicon and Intel. The recorded-click comparison without alignment still differs by up to 145 levels. The 41 px hard dab has a spread of eight levels at the same centered radius, which limits a purely radial model.

The fit used 7, 12 and 21 px dabs at 50%, 75% and 100% hardness. It withheld 13 and 41 px from fitting. The 3 px cases supplied a common small-diameter boundary. Photato interpolates between the measured hardness levels and blends from the 3 px boundary over the 3–5 px range. The Mac was locked, so fresh measurements of exact placement, other hardness values and continuous strokes remain open.

The native API exposes `calibratedRound` on existing brush settings. It is retained by native preset version 3 and Action version 64. Recorded settings with the previous profiles retain their previous rendering. The library upgrades untouched copies of the earlier factory presets. ABR continues to exchange standard round-tip attributes.

All 411 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The 146 legacy raster buffers match build 553 on each architecture. At 5,000 px, the native session and complete rendering agree for tested strokes at 50%, 75% and 100%. Both slices of the macOS 14+ universal archive passed offscreen checks. Physical presentation and tablet cadence remain open.

[Development record](DEVLOG.md#dev-step-554) · [Validation evidence](WIDE_ROUND_HARDNESS_554.json) · [Frozen source](SOURCE_SNAPSHOT_554.json)
