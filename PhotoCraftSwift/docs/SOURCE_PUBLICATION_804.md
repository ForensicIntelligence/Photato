# Source checkpoint 804

Camera Raw Dehaze now applies to supported sensor images above 36 megapixels. All existing Photato spatial Camera Raw controls have a paged path in this build.

The production RAW development command applied Dehaze to the owned 8,192 × 5,120 DNG with contrast and returned 10,240 mapped tiles. Five inspected RGB samples changed, including adjacent rows across a band boundary. The sampled alpha and all source-file bytes were retained. Using the same native decoder and opening path, a separate build 801 Debug probe retained the full 16,000 × 10,000 sensor and original bytes of a canonical DNG.

The exact comparisons use the existing Photato renderer. Adobe Dehaze and RAW output comparisons remain open.

Photato capabilities include Dehaze in `rawDevelopment.pagedTone`, with the same nominal sensor and spatial-adjustment limit. The desktop app and authenticated `raw.develop` share the processing path.

Xcode built the app. All seven focused core tests passed. The new case verifies every stored sample of positive and negative Dehaze in RGB16 and linear Float32, including a combination with local tone and Detail. Both optimized architectures passed all 386 selected cases, including authenticated capability discovery. Intel ran under Rosetta. Both signed Universal slices rendered offscreen.

The camera and RAW layout must be supported at full size by the Apple decoder. The 65,000-pixel side and 512-megapixel area are admission bounds. The installed decoder does not return full-size rasters for the tested canonical DNGs at those two bounds.

The Universal ZIP targets macOS 14 and later. It contains 78,977,581 bytes with SHA-256 `c5aa8487a68c9c938af48cde3a304effaf4d41fbb4ebaf07065c813dc816b6b5`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_804.json) · [Development record](DEVLOG.md#dev-step-804).
