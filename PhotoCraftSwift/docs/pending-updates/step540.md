<a id="dev-step-540"></a>

## 2026-11-17 — Align linear Float32 brush output across architectures

The six differing linear Float32 Brush outputs in build 539 traced back to the single-precision power operation in the extended sRGB transfer. A linked probe of 1,061,749 finite Float32 inputs found 1,837 decode differences and 3,632 encode differences. An independent 80-digit calculation agreed with the widened-power candidate for every one of those differences.

Color.swift now evaluates the power in Double and rounds it to Float32 before continuing. The existing thresholds, Float32 operands and exponents, final Float32 arithmetic, sign reflection and signed-zero behavior remain. LinearSurfaceTests.swift adds exact expected words in both directions, including negative input, HDR overflow and unchanged alpha. Existing linear raster data stays in its stored representation.

The standalone candidate matched across the two architectures for all 2,139,095,040 nonnegative finite Float32 bit patterns. The production builds match each other and the candidate over the same exhaustive nonnegative range. Signed inputs were covered by the sampled probe and exact unit cases. The sRGB specification describes the transfer curve. The native measurements establish architecture agreement for the tested workflows. [Extended sRGB transfer](https://www.w3.org/TR/css-color-4/#color-conversion-code).

The first compiled candidate passed 240 focused methods in Debug and both optimized architectures. Seven additional Photoshop-reference compositing methods passed in each configuration. The complete transfer probe and 32 Brush buffers agreed across both architectures. Broader checks found exact owned Auto-Blend and Gradient Map references still using previous Apple Silicon conversion results. Independent calculations reproduced the changes in every affected word. The old fixture bytes and the first test attempt were saved.

The first 990 px linear Brush benchmark also recorded a higher render time. It used an implicit, uniform source that repeated the same sRGB conversion for every pixel in a tile. The second qualification verifies caching that value for implicit tiles and compares uniform and dense sources. The wider rendering checks also retained earlier failures involving a Gradient Fill PSD tag and a stale API command count.

The first candidate took longer in the linear soft-dab measurement. Surface.swift now reuses the encoded source value across each implicit background tile. BrushDynamicsTests.swift also checks the default-tile callback against the individual setter and protects hidden RGB, padding and partial tiles. The owned Auto-Blend and Gradient Map regressions use independently corrected output values and retain their original fixture files.

All 251 selected methods pass in Debug, optimized Apple Silicon and Intel under Rosetta. Both universal executables passed the offscreen workspace check. All 32 Brush cases now agree across architectures. The 24 integer or encoded Float32 outputs match build 539, as do the 24 earlier small-dab measurements. The same shared conversion serves both desktop and API operations. The API and archive schemas stay at their current versions. Hosted large-tip cadence and Photoshop Brush pixel comparisons remain open. [Qualification](SOURCE_PUBLICATION_540.md).

A separate hosted AppKit run compared the 64, 1,800, 2,500 and 5,000 px brushes against build 538 on a 24 MP layered document. Build 540 drew 119 times during the two-second 64 px stroke. The 5,000 px stroke first drew after 3.70 seconds and drew 0 times during input. All eight cases match a complete stroke and pass commit and Undo. These timestamps locate a large-brush processing delay in the application. Display and stylus measurements remain open.
