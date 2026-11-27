# Source checkpoint 759

Opening eligible 8-bit and 16-bit RGB PNGs preserves colour beneath transparent pixels. The reader keeps straight samples in the working space, including alpha zero and the smallest nonzero alpha. The existing conversion still handles colour-space changes and providers outside the supported layout and size budget.

The desktop and authenticated Photato import paths preserve 8-bit and 16-bit samples. The Adobe-compatible action input uses the same reader within its current RGB8 limit. Import commands and schemas stay the same.

All 33 selected Xcode Debug checks passed, including native archive and HTTP import. All 135 focused optimized checks passed on each architecture, including the two new tests. Intel ran under Rosetta.

All 3,840 decoded RGBA bytes matched in three owned Photoshop PNGs. Three synthetic PNGs also matched 1,064,960 decoded bytes with and without an embedded RGB profile. The 16-bit controls span all 65,536 red sample values in both ordinary and Adam7-interlaced files. A 36-megapixel control preserved the 20 sampled bytes while mapping four document tiles totalling 256 KiB. That storage figure excludes ImageIO’s decoded provider. Whole-file PNG equality remains unverified.

The signed Universal ZIP targets macOS 14+ and both extracted slices rendered offscreen. The 77,916,037-byte archive has SHA-256 `65fccb029f2bc62db2bde265b9a565cb2f627906414134e6b6042a053322b829`.

[Adobe Execute Actions guide](https://developer.adobe.com/firefly-services/docs/photoshop/guides/execute-actions/)

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_759.json) · [Development record](DEVLOG.md#dev-step-759).
