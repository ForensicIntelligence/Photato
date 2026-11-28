# Source checkpoint 774

Photato opens supported tiled classic TIFFs as editable images. The native decoder retains color components, opacity and profiles and trims the physical tile padding at the image edges.

Independently authored rectangular CMYK16 tiles matched all 141,932 color words and retained 225 ppi. Six more RGB8, Gray16 and RGB32 controls matched all 94,900 authored samples across raw, LZW and ZIP. The checks include both byte orders, interleaved and planar layouts, straight opacity and floating-point prediction.

Authenticated Photato uploads and Adobe-compatible action resources use the same native tile decoder. The exercised CMYK input retained all raw component values and resolution through both entry points.

Xcode built the native app. All 15 selected imaging and 8 app and HTTP tests passed. Both optimized architectures passed all 252 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on both slices.

TIFF output continues to use strips. Further layered or associated-alpha tile combinations, JPEG-compressed component TIFFs, BigTIFF and wider Photoshop byte comparisons remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,131,745 bytes with SHA-256 `09cb052c1e00b2034f1c03e256822107424f6f5e1d7e36d2b23e75d597f508b3`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_774.json) · [Development record](DEVLOG.md#dev-step-774).
