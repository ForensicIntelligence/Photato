# Source checkpoint 767

The TIFF save panel now has an Embed Color Profile checkbox. It follows the document’s profile choice by default and accepts a per-file override. The TIFF writer preserves the sample values with either choice.

An independent decoder matched all 2,048 Gray16 samples with the Photoshop references in four profile cases on each architecture. Tagged and untagged copies also matched those samples when saved through the native Photato panel. The imaging tests cover flat and layered RGB, grayscale, CMYK and Lab, plus Indexed Color without an embedded profile.

The native save panel, authenticated Photato TIFF downloads and Photato resource jobs share the optional `tiffEmbedProfile` setting. Omission uses the document’s profile choice. The published Adobe TIFF request schema is unchanged.

The Xcode project built and 39 focused imaging and 12 app, panel and HTTP tests passed. Both optimized architectures passed all 227 selected tests. The extracted Universal preview rendered offscreen on each slice. Intel ran under Rosetta.

The checks establish TIFF profile choice and sample preservation in the tested cases. Photoshop TIFF opacity, whole-file equivalence and larger component TIFF documents are still open.

The signed Universal ZIP targets macOS 14 and later. It contains 77,990,883 bytes with SHA-256 `c44daa8a766a6b372e067d62eeb1ea62db7484cc67c3aa0430f958d2fef0b2c2`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_767.json) · [Development record](DEVLOG.md#dev-step-767).
