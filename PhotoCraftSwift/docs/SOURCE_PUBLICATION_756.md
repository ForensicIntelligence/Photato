# Source checkpoint 756

TIFF Save Transparency controls the merged preview. Turning it off composites the preview over white and omits the merged opacity sample. Editable layers, layer masks and named saved selections retain their samples. The checkbox starts checked, preserving the previous Photato export behaviour.

Native Save and authenticated Photato transfers share the TIFF implementation. `tiffTransparency` can be true or false and defaults to the existing transparent export. The Adobe-compatible endpoint uses the published options for its output.

All 21 focused Xcode Debug checks and 81 optimized cases per architecture passed. The selected scope covers TIFF, raster encoding options, native save options and API transfers. Each architecture passed the four new regression tests. Intel ran under Rosetta. The expanded baseline inventory remains documented with checkpoint 755.

The independent TIFF parser confirmed the measured white-matte equation across all 9,216 colour samples and an unchanged 3,072-byte selection channel. The matched matted output differs from Photoshop by one sample value in 316 red, 50 green and 104 blue samples. Other colour modes and the Photoshop factory checkbox default still need reference checks.

The signed Universal ZIP targets macOS 14+ and both extracted slices rendered offscreen. The 77,889,139-byte archive has SHA-256 `b2b5f3a0b165213d44560babb0d52a564fa34c1f94d961f81676f64fec57e684`.

[Adobe’s TIFF save options](https://helpx.adobe.com/photoshop/desktop/save-and-export/save-files/save-in-tiff-format.html)

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_756.json) · [Development record](DEVLOG.md#dev-step-756).
