# Source checkpoint 592

Native Swift 0.3.0, build 592, 19 November 2026. Smart Filter masks accept Feather through 1,000 px and render projected mask regions on sparse large documents.

The maximum logical 300,000 × 300,000 test keeps the original Smart Object editable and updates two separated mask regions. Thirty-six dense-versus-paged comparisons agree byte-for-byte. An independent comparison matched 90 earlier native outputs on each architecture. A separate 300,000 × 64 Float32 raster exercises a non-uniform mask at 1,000 px. Properties, HTTP, Undo and native archive round trips pass. A hosted AppKit check shows the real Filter Mask controls in light and dark appearance. [Photoshop Smart Filter masks](https://helpx.adobe.com/photoshop/desktop/effects-filters/smart-filters/mask-smart-filter-effects.html) · [Feather range](https://developer.adobe.com/photoshop/uxp/ps_reference/classes/layer/).

All 887 selected checks passed in Debug, optimized Apple Silicon, and Intel under Rosetta. Both extracted universal slices passed offscreen checks, and the archive declares macOS 14 as its minimum. Larger radii use Photato’s streamed area filter pending Photoshop coverage measurements. Physical Intel, physical macOS 14, live slider input, wide dense performance, and editable PSD/PSB Feather remain open.

[Developer record](DEVLOG.md#dev-step-592) · [Validation data and source fingerprints](SMART_FILTER_MASK_FEATHER_592.json).
