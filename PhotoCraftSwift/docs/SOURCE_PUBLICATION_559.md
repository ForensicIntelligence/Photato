# Source checkpoint 559

Native Swift 0.3.0, build 559, 18 November 2026. Paint Bucket has a Clear mode, a typed Photato API, and bounded writeback for separated sparse and full solid fills. Clear reduces alpha on an unlocked 8- or 16-bit pixel layer. The cursor shows subtraction and Option displays foreground sampling. Clear uses opacity and region or selection coverage. In this implementation a pattern's alpha also weights the removal. [Adobe Paint Bucket](https://helpx.adobe.com/photoshop/desktop/apply-painting-techniques/fill-objects-selections-layers/fill-paint-bucket-tool.html) · [Adobe blending modes](https://helpx.adobe.com/photoshop/desktop/repair-retouch/adjust-light-tone/blending-mode-descriptions.html).

The `paint.bucket` command can configure native settings or fill using overrides. The native click and service capture the same sampling, pattern and placement in one prepared edit. Configuration advances the tool revision without editing the document. Tests check native and HTTP output, protected targets, modifier feedback, one Undo, and maximum-size sparse pattern and full or partial solid fills. [Adobe Photoshop API v2](https://developer.adobe.com/firefly-services/docs/photoshop/api/photoshop-v2/).

All 486 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. The 240 color-region masks and 18 ordinary bucket buffers match build 558 byte for byte on both architectures. Each optimized slice also matched 624 bounded raster samples between dense and paged solid Bucket writeback at multiple opacities, blend modes and transparency protections. Both slices of the macOS 14+ universal archive passed offscreen checks.

The desktop remained locked. Exact Photoshop bucket output, pattern clearing behavior, and live interactions still need a controlled comparison. Paint Bucket Actions, dense maximum-size pattern writeback and Clear in Edit Fill/Stroke remain open.

[Development record](DEVLOG.md#dev-step-559) · [Validation evidence](PAINT_BUCKET_CLEAR_559.json) · [Frozen source](SOURCE_SNAPSHOT_559.json)
