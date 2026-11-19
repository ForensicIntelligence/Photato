# Source checkpoint 591

Native Swift 0.3.0, build 591, 19 November 2026. Aligned 32-bit raster masks now use Photoshop’s measured filter schedules at 14 fractional Feather settings.

Apple Silicon matches all 11,389 stored texture, line, step and edge samples. Intel matches 11,384 of 11,389, with the five differences limited to one Float32 step. Independent PSD readback confirms the textured cases. The reference files came from the ad-hoc-signed Photoshop 27.2.0 installation on this Mac. [Adobe layer-mask property](https://developer.adobe.com/photoshop/uxp/ps_reference/classes/layer/).

All 861 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both extracted universal slices passed offscreen checks. The archive declares macOS 14 as its minimum. Physical Intel and macOS 14 validation, arbitrary affine masks, additional fractional settings, and the separate vector and Smart Filter mask paths remain open.

[Developer record](DEVLOG.md#dev-step-591) · [Validation data and source fingerprints](FRACTIONAL_RGB32_FEATHER_591.json).
