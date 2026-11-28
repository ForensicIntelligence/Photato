# Source checkpoint 797

Command–S opens Save Image from the local Camera Raw source workspace. The same native format controls can save TIFF, JPEG, PNG or PSD with the current adjustments and output settings. The source stays open for further adjustment.

The signed native app saved a 512 × 384 RGB16 sRGB TIFF with Exposure set to +0.75. Cancelling a second save kept the adjustment visible. Closing Camera Raw preserved the DNG and left the directory without an XMP sidecar.

Adobe’s Camera Raw Save Options also exposed JPEG XL, AVIF and DNG. Photato keeps sensor-preserving DNG Copy in the existing settings menu.

The development and encoder path is available through authenticated RAW import with `X-Photato-Raw-Open-Mode: copy`, optional XMP and workflow headers, and the existing format download. The capability response advertises this workflow. The four tested native and HTTP encoding results were byte-identical.

Xcode built the app and the focused test verified all four file formats through the native encoder and authenticated API. Both optimized architectures passed all 368 selected tests. Intel ran under Rosetta. Both Universal preview slices rendered offscreen.

Rendered JPEG XL and AVIF destinations, output sharpening, installed ICC choices and Adobe RAW pixel and file-byte parity remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,726,877 bytes with SHA-256 `498c96c04bee86cafe9b013a7568e4fccfb796b9dc84cfedff67c8e6ea1518a3`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_797.json) · [Development record](DEVLOG.md#dev-step-797).
