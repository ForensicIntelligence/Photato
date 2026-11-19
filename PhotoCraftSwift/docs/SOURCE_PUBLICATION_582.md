# Source checkpoint 582

Native Swift 0.3.0, build 582, 18 November 2026. Supported raster clipping merges and stamps preserve Blend Clipped Layers as Group, the base blend mode, and its opacity. The native editor, Photato HTTP API and both local Adobe-compatible job routes use the same compositor. [Adobe advanced blending options](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/apply-layer-effects/use-advanced-blending-options.html).

The reference set covers eight Normal-base and 15 Multiply-base results, including stored alpha, partial opacity and backdrop controls. The Multiply cases use Photoshop outputs saved on both architectures at RGB8, RGB16 and RGB32. The Normal cases use the previously saved Apple Silicon files.

All 85 focused Debug checks and 773 selected checks per configuration passed. Both slices of the extracted signed universal archive passed offscreen checks. The archive declares macOS 14 as its minimum.

Masked clipping, adjacent non-Normal clipped layers and physical platform tests remain open.

[Developer record](DEVLOG.md#dev-step-582) · [Validation data and source fingerprints](INDEPENDENT_CLIPPING_REFERENCES_582.json).
