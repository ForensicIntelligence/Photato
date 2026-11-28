# Source checkpoint 780

Eligible opaque RGB8 and RGB16 TIFFs now stream directly into editable tiles. The same path reads classic TIFF and BigTIFF while keeping the original document bit depth.

A 27,000 × 27,000 uncompressed RGB16 BigTIFF was opened and saved through the native codec. The output directory was beyond 4 GiB. An independent libtiff read verified all 2,187,000,000 components against the quantization measured in Photoshop. All 53,055 TIFF samples in the separate Photoshop 27.2 reference matched Photato exactly. The 4,099 × 521 output files from builds 779 and 780 were byte-identical.

File Open and the existing authenticated Photato import and supported Adobe-compatible asset input share the optimized decoder. Existing request schemas and HTTP size limits apply.

Xcode built the native app. All 5 focused imaging and 2 focused app and HTTP tests passed. Both optimized architectures passed all 274 selected tests, with Intel running under Rosetta. Both slices of the Universal preview rendered offscreen.

The dense test covers a flattened, untagged, interleaved RGB16 image without transparency. Dense layered files, other color modes and profiles, and full-format byte equality remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,222,822 bytes with SHA-256 `d8e8a01f4b3ecc4ccbbb17e1ca9f0e40f4b0eb557f377edadfa3e57a93cdb7eb`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_780.json) · [Development record](DEVLOG.md#dev-step-780).
