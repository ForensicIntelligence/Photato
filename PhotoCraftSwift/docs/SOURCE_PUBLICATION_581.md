# Source checkpoint 581

Native Swift 0.3.0, build 581, 18 November 2026. Merge Down and Stamp Down now work between adjacent Normal raster clips in the same clipping stack. The native editor, Photato HTTP and both local ActionJSON routes use the same implementation. [Adobe layer commands](https://helpx.adobe.com/photoshop/desktop/create-manage-layers/get-started-layers/merge-and-stamp-layers.html).

Saved Photoshop references cover RGB8, RGB16 and RGB32, partial opacity, clipped row retention and hidden destination rejection. The 300,000 × 300,000 sparse fixture tests two distant raster patches. The background RGB32 ActionJSON stack overflow was repaired by eliminating recursive document preparation from the merge compositor.

All 81 focused Debug checks and 769 selected checks per configuration passed. Both slices of the extracted signed universal archive passed offscreen checks. The archive declares macOS 14 as its minimum.

Independent clipping, adjacent non-Normal clips, broader Photoshop parity and physical platform qualification remain open.

[Developer record](DEVLOG.md#dev-step-581) · [Validation data and source fingerprints](ADJACENT_CLIP_REFERENCES_581.json).
