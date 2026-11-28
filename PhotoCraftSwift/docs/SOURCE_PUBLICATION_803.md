# Source checkpoint 803

Camera Raw can adjust Highlights, Shadows, Texture and Clarity on supported sensor images above 36 megapixels. The native processor uses the full image dimensions to choose the filter radii.

The production RAW development command applied all four controls to the owned 8,192 × 5,120 DNG and returned 10,240 mapped tiles. Five inspected RGB samples changed, including adjacent rows across a band boundary. The sampled alpha and all source-file bytes were retained.

The output comparisons use the existing Photato renderer. Adobe tone and RAW output comparisons remain open.

The same controls run in the desktop app and authenticated `raw.develop`. Photato capabilities list the four controls in `rawDevelopment.pagedTone`.

Xcode built the app. All six focused core tests passed. The new test covers RGB16 and linear Float32 with partial alpha, both with and without Detail sharpening. Each stored sample matches the dense Photato renderer. Both optimized architectures passed all 385 selected cases, including authenticated capability discovery. Intel ran under Rosetta. Both signed Universal slices rendered offscreen.

Dehaze still has a 36-megapixel limit in this build. The maximum RAW sensor dimensions depend on the Apple decoder.

The Universal ZIP targets macOS 14 and later. It contains 78,959,510 bytes with SHA-256 `b81cdc531964c31a56b0df78306f7fffc85022cfaffb8ad7b3827ef87904fd9c`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_803.json) · [Development record](DEVLOG.md#dev-step-803).
