# Source checkpoint 776

Photato opens opaque Gray8 and RGB8 JPEG-compressed classic TIFFs as editable images. The decoder handles strips, rectangular tiles and separate RGB channels and keeps the original resolution, profiles and supported editable TIFF layers.

All 346,365 color samples from seven authored TIFFs matched the full-file ImageIO TIFF decoder. The five grayscale and explicit RGB fixtures also matched all 207,819 samples from an independent libtiff decode. Photoshop 27.2 opened the grayscale tile and subsampled YCbCr strip references. Against their lossless Photoshop copies, 484 of 23,091 gray samples differed by one code. 65,314 of 69,273 YCbCr-derived RGB samples differed, with a mean of 14.14 and maximum of 123 codes on the high-chroma pattern.

Native file Open, authenticated Photato uploads and Adobe-compatible action resource decoding share this TIFF reader. The API test compares all grayscale and opacity samples across these paths without changing Adobe request fields.

Xcode built the native app. All 3 focused imaging and 1 focused app and HTTP tests passed. Both optimized architectures passed all 259 selected tests, with Intel running under Rosetta. The extracted Universal preview rendered offscreen on both slices.

Photoshop color reconstruction and JPEG IDCT rounding still differ on the measured inputs. JPEG TIFF save, legacy JPEG compression and additional component, density and corruption cases remain open.

The Universal ZIP targets macOS 14 and later. It contains 78,174,151 bytes with SHA-256 `bf290994af8f1f3e668760b173d6745fc74a9e5a536ab9a092b990cd74d3c1a0`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_776.json) · [Development record](DEVLOG.md#dev-step-776).
