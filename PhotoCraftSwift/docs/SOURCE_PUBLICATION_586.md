# Source checkpoint 586

Native Swift 0.3.0, build 586, 19 November 2026. Pixel-mask Feather now renders requested regions on 300,000 × 300,000 documents without preparing a full padded mask. [Adobe's layer-mask guide](https://helpx.adobe.com/ee/photoshop/how-to/fine-tune-layer-masks.html).

The retained Feather samples are bounded to 1 MiB per mask sampler. Tests preserve prior Photato coverage words under the supported transforms, density and inversion. They check the existing 100 px radius at a maximum-size mask corner and compare both regional compositor paths in RGB8, RGB16 and RGB32. The Photato API reports the capability through raster storage discovery.

All 842 selected tests passed in Debug, optimized Apple Silicon and Intel under Rosetta. Both slices of the extracted ad-hoc-signed universal archive passed the offscreen smoke test. Both declare macOS 14 as the minimum. The tests ran on the development Mac. Physical Intel, macOS 14 and live editing qualification remain open.

The separate Photoshop references confirm 100, 250 and 1,000 px Feather and help explain its numerical behavior. Captures came from the installed ad-hoc-signed Photoshop 27.2.0. The shipping radius remains 100 px while the wider kernel is being qualified. Broader mask and clipping workflows remain in development.

[Developer record](DEVLOG.md#dev-step-586) · [Validation data and source fingerprints](BOUNDED_MASK_FEATHER_586.json).
