# Source checkpoint 757

Normal blends between supported aligned 8-bit RGB raster layers use the measured integer compositing formula. The dense, paged and sparse render paths share the arithmetic. Default pixel masks remain editable.

The desktop renderer and the existing authenticated render and file routes share the same RGB8 arithmetic. The established API options and file schemas continue to apply.

All 22 focused Xcode Debug checks passed, including native Save and authenticated transfers. All 131 selected optimized tests passed on each architecture. The suite covers TIFF, raster encoding, Normal layer blends, layer-layout and group rendering, and file transfer options. Intel ran under Rosetta.

The two owned Photoshop TIFF captures and the committed output regression match all 27,648 sampled colour, opacity, and saved-selection bytes with Save Transparency enabled and disabled. The independent TIFF strip reader compared the Adobe-authored files against outputs from the original PSD. Whole TIFF files retain different container bytes. An independent 131,072-pixel Normal merge comparison also matched all visible samples and opacity. Hidden RGB at zero opacity remains different in two merge-fixture variants.

The signed Universal ZIP targets macOS 14+ and both extracted slices rendered offscreen. The 77,894,938-byte archive has SHA-256 `4d1f878d0d09696b6b62d5506a8621b2d8c24b47944fbcf6fa287a7dc93cfd29`.

[Adobe’s TIFF save options](https://helpx.adobe.com/photoshop/desktop/save-and-export/save-files/save-in-tiff-format.html)

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_757.json) · [Development record](DEVLOG.md#dev-step-757).
