# Source checkpoint 764

Open can now expand larger PNG palettes with partial opacity or multiple transparent entries into editable RGB8. The importer streams packed scanlines to scratch storage and builds file-backed RGB tiles. It handles standard and Adam7 layouts and applies EXIF rotations.

Desktop Open, authenticated Photato import and both action resource interfaces use the same paged decoder. The two resource paths passed the 8.39-megapixel test. Existing compressed input, scratch and operation limits still apply.

All 36 focused imaging cases and eleven app and HTTP cases passed in Xcode Debug. Both optimized architectures passed all 225 selected tests. Intel ran under Rosetta.

Photato had rejected the 8,389,632-pixel palette control. Photoshop 27.2.0 opened it in RGB8. The revised Photato reader matched all 8,389,632 original straight RGBA samples in an independent replay. The sparse 36,006,000-pixel Adam7 test retained all sampled colors and opacity. The EXIF rotation test kept the canvas file-backed and moved the tested pixels to their expected positions.

Photoshop’s PNG copy preserved all visible color and opacity in the 8.39-megapixel control. Its save normalized hidden RGB at 8,192 fully transparent positions. Export container equality remains open.

The new path applies to palettes that require RGB expansion. Editable Indexed Color and Bitmap still use their existing size limit. Maximum-size dense imports and animated PNG remain open.

The signed Universal ZIP targets macOS 14 and later. Both extracted architectures rendered offscreen. The 77,972,744-byte ZIP has SHA-256 `cc2fbf5d2fbd211d2b95ac7dcaf614d983661c3d0215e242bb197827c1894f98`.

[PNG palette transparency specification](https://www.w3.org/TR/png-3/#11tRNS).

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_764.json) · [Development record](DEVLOG.md#dev-step-764).
