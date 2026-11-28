# Source checkpoint 770

Photato opens supported large classic RGB8, RGB16 and RGB32 TIFF strips as ordinary editable RGB rasters and writes large copies through bounded regions. The files retain working profiles and the selected transparency behavior.

A 9,000 × 8,000 RGB16 control opened above 512 MiB, saved as a 576 MB TIFF and reopened with its ICC profile and measured opacity samples. An independent parser matched all 288 million packed color and alpha words against the authored raster and established document encoder samples. Focused RGB8, RGB16 and RGB32 packing checks compare standard and Display P3 profiles, profile embedding and transparency choices against the established encoder.

Authenticated Photato uploads and action resources share the expanded TIFF input, including hidden straight RGB samples. The TIFF writer targets local files and Data through the same compression, endian and profile options. HTTP transfer limits still apply.

The native Xcode target built and all three new imaging and six selected app/HTTP tests passed. Both optimized architectures passed all 241 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on each slice.

The checks cover selected classic RGB strip inputs and output. Large saved auxiliary channels, component tiles, JPEG-in-TIFF, BigTIFF and complete Photoshop sample and storage comparisons remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,062,246 bytes with SHA-256 `5d84d134f78f310d44daa06c13a0ceb1e576891686ff757ccf1a02bb146f2f09`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_770.json) · [Development record](DEVLOG.md#dev-step-770).
