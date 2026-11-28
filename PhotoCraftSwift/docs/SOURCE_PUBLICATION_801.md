# Source checkpoint 801

Camera Raw can apply Post Crop Vignetting and Grain to images above 36 megapixels. The workspace and Photato API use the same adjustment pipeline.

An offscreen run through the RAW development command processed the owned 8,192 × 5,120 DNG into 10,240 mapped tiles. It changed each of five inspected points, including adjacent rows across a band boundary. The inspected alpha and all original sensor file bytes were preserved.

This change compares the two Photato rendering paths. Direct Adobe comparison still needs controlled vignette and grain references.

The authenticated Photato capabilities publish vignette and grain under `rawDevelopment.pagedEffects`. The same controls are used by `raw.develop`.

Xcode built the app. All three focused core tests passed. The new case compares every sample of paged and dense output for all three vignette styles with grain and partial alpha in RGB16 and linear Float32. Both optimized architectures passed all 382 selected cases. Intel ran under Rosetta. Both signed Universal slices rendered offscreen.

Sharpening, noise reduction, shadows, highlights, clarity, texture and dehaze still use the 36-megapixel limit in this build. Camera compatibility and full-resolution admission depend on the Apple decoder.

The Universal ZIP targets macOS 14 and later. It contains 78,871,440 bytes with SHA-256 `19772bc63382e0ab31fd8930300e161ee8afac0448857a1a517954e67a5843a2`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_801.json) · [Development record](DEVLOG.md#dev-step-801).
