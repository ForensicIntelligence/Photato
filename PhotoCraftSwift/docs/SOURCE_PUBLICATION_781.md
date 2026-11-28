# Source checkpoint 781

Layered TIFF and BigTIFF now keep saved alpha and spot plates in RGB, Grayscale, CMYK and Lab. Associated or straight composite opacity stays separate from the named channels. Names, display colors, spot solidity and channel IDs survive Open and lossless Save.

Photoshop 27.2 opened the final Photato RGB8, RGB16 and RGB32 BigTIFFs with both Proof ink and Alpha 2 visible in Channels and with Coating selected in the editable layer stack. LibTIFF independently matched all 17,286 alpha and spot samples, including the Float32 words. Native tests also round-tripped RGB, Grayscale, CMYK and Lab fixtures.

Native Save, Photato import, download and Save As, and Adobe-compatible asset input share the same channel handling. Lossless copy and download retain editable channels with `tiffLayers: true`. The published Adobe output schema and existing transfer size limits remain in effect.

Xcode built the native app. All 5 focused imaging and 2 focused app and HTTP tests passed. Both optimized architectures passed all 297 selected tests, including PSD channel and spot operations. Intel ran under Rosetta. Both slices of the Universal preview rendered offscreen.

Flattened TIFF alpha and spot output, Quick Mask, very large layered files and byte identity for complete Photoshop files remain open. Some rich Photoshop blocks still require big-endian TIFF or PSD.

The Universal ZIP targets macOS 14 and later. It contains 78,213,342 bytes with SHA-256 `226c4f1e4aacdce85976c1dc9f62c9de17be5b7954729f77fdf402882ab8e941`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_781.json) · [Development record](DEVLOG.md#dev-step-781).
