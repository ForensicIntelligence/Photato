# Source checkpoint 590

Native Swift 0.3.0, build 590, 19 November 2026. Aligned RGB8 and RGB16 raster-layer masks now use integer-rounded Feather stages in rendering and clipping merges.

The same working-domain and rounding rules reproduce 51,578 stored colour words across 34 editable Photoshop controls at 0.5, 1.25, 3.5, 4, 8, 100 and 250 px. The independent stored PSD check passed on all three Photato configurations. The reference files came from an ad-hoc-signed Photoshop 27.2.0 installation on Apple Silicon. [Photoshop PSD format](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/).

All 858 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both extracted universal slices passed offscreen checks, and the archive declares macOS 14 as its minimum. Physical Intel and macOS 14 validation, independent Photoshop Rosetta references, other fractional and affine settings, and the separate vector and Smart Filter mask paths remain open.

[Developer record](DEVLOG.md#dev-step-590) · [Validation data and source fingerprints](INTEGER_MASK_FEATHER_590.json).
