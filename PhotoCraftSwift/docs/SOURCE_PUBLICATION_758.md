# Source checkpoint 758

PNG exports retain straight colour and alpha samples in 8-bit and 16-bit RGB. In supported Normal raster stacks, the PNG export follows Photoshop’s observed behaviour for RGB beneath fully transparent pixels.

Native Save, authenticated Photato downloads and the Adobe-compatible action-job output share the same PNG encoder. Compression, interlacing, save policy and API schemas continue to apply.

All 31 selected Xcode Debug checks passed, including native save and API checks. All 133 focused optimized checks passed on both architectures, including the new PNG checks for Adam7 interlacing and very low opacity. Intel ran under Rosetta.

All 3,840 decoded RGBA bytes in three owned Photoshop PNG exports matched, covering RGB8, RGB16 and RGB8 offset layers. The PNG containers still differ in metadata and compression. The Open path in this checkpoint still discards hidden RGB beneath zero alpha.

The signed Universal ZIP targets macOS 14+ and both extracted slices rendered offscreen. The 77,903,862-byte archive has SHA-256 `5b823cd0e64bd5be62b432905d23fe060d5d06525fa1c1b8a4db09e7ece2aa9a`.

[Adobe’s Save a Copy workflow](https://helpx.adobe.com/photoshop/desktop/save-and-export/save-files/save-your-work.html)

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_758.json) · [Development record](DEVLOG.md#dev-step-758).
