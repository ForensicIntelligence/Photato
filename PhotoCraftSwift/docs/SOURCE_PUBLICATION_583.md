# Source checkpoint 583

Native Swift 0.3.0, build 583, 18 November 2026. Multiply, Darken, Lighten and Difference now participate in supported raster clipping merges and stamps at 8, 16 and 32 bits per channel. The native editor, Photato HTTP API and both local Adobe-compatible job routes share the implementation. [Adobe's blending options](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/apply-layer-effects/use-advanced-blending-options.html).

The 12 saved operation results per architecture include partially opaque clips and transparent and partially opaque base samples. The tested outputs matched all 62,736 stored sample words on Apple Silicon and under Rosetta. The fixture manifest identifies the project-owned PSD inputs and expected outputs.

All 88 focused Debug checks and 776 selected checks per configuration passed. Both slices of the extracted signed universal archive passed offscreen checks. The archive declares macOS 14 as its minimum.

Editable clipping masks, more complex layer content and other blend modes remain in development. Physical Intel and macOS 14 execution remain unverified.

[Developer record](DEVLOG.md#dev-step-583) · [Validation data and source fingerprints](CLIPPED_BLEND_MODE_REFERENCES_583.json).
