# Source checkpoint 802

The Camera Raw Detail controls can sharpen and reduce luminance and color noise in eligible images above 36 megapixels. The app filters native Float32 scratch planes on disk, using the same edge handling as the dense renderer.

An offscreen run through the RAW development command processed the owned 8,192 × 5,120 DNG with all three Detail controls into 10,240 mapped tiles. Five inspected RGB samples changed, including adjacent rows across a band boundary. The sampled alpha and all source-file bytes were retained. Apple Silicon Release processed the adjustments in 23.46 seconds and reproduced every inspected Debug sample.

The exact comparisons use Photato’s dense renderer as the reference. Adobe comparison remains open.

The authenticated Photato capabilities list these controls in `rawDevelopment.pagedDetail` and identify the remaining `limitedLargeAdjustments`. The `raw.develop` command shares the desktop processing path.

Xcode built the app. All five focused core tests passed. The new cases compare filter-stage Float32 words and every stored sample of the RGB16 and linear Float32 result. Both optimized architectures passed all 384 selected cases, including authenticated capability discovery. Intel ran under Rosetta. Both signed Universal slices rendered offscreen.

Shadows, highlights, clarity, texture and dehaze still use the 36-megapixel limit. The source must be supported at full size by the Apple decoder. Adobe output sharpening is separate from the Detail Sharpening control.

The Universal ZIP targets macOS 14 and later. It contains 78,917,956 bytes with SHA-256 `eb7e2b946cdfe54fda215f84f77bbb6875601528ddb996fe433fce15999c100d`.

[Universal download](../../downloads/Photato-universal.zip?raw=1) · [Machine-readable evidence](SOURCE_PUBLICATION_802.json) · [Development record](DEVLOG.md#dev-step-802).
